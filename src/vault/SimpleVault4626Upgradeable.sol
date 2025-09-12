// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {ISimpleAdapter} from "../interfaces/ISimpleAdapter.sol";

interface INGORegistrySimple {
  function isAllowed(address ngo) external view returns (bool);
}

interface IDonationPayer {
  function donate(address asset, address ngo, uint256 amount) external;
}

/// @title SimpleVault4626Upgradeable
/// @notice ERC-4626 vault with fixed donation split per vault, harvest without epochs, and strict withdraw-always-open.
contract SimpleVault4626Upgradeable is
  ERC4626Upgradeable,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20 for IERC20;

  // ---- Constants ----
  uint16 public constant MAX_FEE_BPS = 150; // 1.5%
  uint16 public constant MAX_LOSS_BPS = 10_000; // bounds for unwind
  uint256 public constant NGO_SWITCH_DELAY = 48 hours;

  // ---- Config ----
  address public guardian; // can pause deposits and trigger emergencyUnwind
  ISimpleAdapter public adapter; // single venue adapter
  address public treasury; // fee recipient
  IDonationPayer public donationPayer; // donation transfer helper
  INGORegistrySimple public ngoRegistry; // allowlist for NGOs

  uint16 public donationPercentBps; // 5000 / 7500 / 10000
  uint16 public protocolFeeBps; // <= MAX_FEE_BPS
  uint256 public tvlCap; // 0 => no cap

  // ---- NGO switching ----
  address public currentNGO;
  address public pendingNGO;
  uint256 public pendingNGOEta;

  // ---- Harvest window / pause ----
  uint256 public harvestWindowBlocks;
  uint256 public harvestWindowOpenBlock;
  uint256 public harvestWindowCloseBlock;
  bool public depositsPaused;

  // ---- Harvest accounting ----
  uint256 public assetsAtLastHarvest;
  uint256 public inflowSinceLast;
  uint256 public outflowSinceLast;

  // ---- Events ----
  event Harvest(uint256 harvested, uint256 fee, uint256 donated, uint256 retained, address indexed ngo);
  event DepositsPaused(bool state);
  event GuardianSet(address indexed oldGuardian, address indexed newGuardian);
  event TVLCapSet(uint256 cap);
  event ProtocolFeeSet(uint16 bps);
  event CurrentNGOSet(address indexed oldNGO, address indexed newNGO, uint256 eta);
  event CurrentNGOSwitched(address indexed oldNGO, address indexed newNGO);
  event EmergencyUnwind(uint16 maxLossBps, uint256 realizedAssets);

  // ---- Errors ----
  error FeeAboveMax();
  error InvalidParam();
  error DepositsPausedErr();
  error HarvestWindowOpen();
  error NotGuardianOrOwner();
  error NGOForbidden();
  error NGONotReady();

  // ---- Initializer ----
  function initialize(
    IERC20 asset_,
    string memory name_,
    string memory symbol_,
    address adapter_,
    address treasury_,
    address donationPayer_,
    address ngoRegistry_,
    address owner_,
    address guardian_,
    uint16 donationPercentBps_,
    uint16 protocolFeeBps_,
    uint256 tvlCap_,
    uint256 harvestWindowBlocks_
  ) external initializer {
    if (donationPercentBps_ != 5000 && donationPercentBps_ != 7500 && donationPercentBps_ != 10_000) revert InvalidParam();
    if (protocolFeeBps_ > MAX_FEE_BPS) revert FeeAboveMax();
    if (adapter_ == address(0) || treasury_ == address(0) || donationPayer_ == address(0) || owner_ == address(0)) revert InvalidParam();

    __ERC4626_init(asset_);
    __Ownable_init(owner_);
    __ReentrancyGuard_init();

    adapter = ISimpleAdapter(adapter_);
    treasury = treasury_;
    donationPayer = IDonationPayer(donationPayer_);
    ngoRegistry = INGORegistrySimple(ngoRegistry_);
    guardian = guardian_;
    donationPercentBps = donationPercentBps_;
    protocolFeeBps = protocolFeeBps_;
    tvlCap = tvlCap_;
    harvestWindowBlocks = harvestWindowBlocks_;

    // Set baseline to adapter + vault balances to avoid double counting on first harvest
    assetsAtLastHarvest = totalAssets();
  }

  // ---- Roles ----
  modifier onlyGuardianOrOwner() {
    if (msg.sender != guardian && msg.sender != owner()) revert NotGuardianOrOwner();
    _;
  }

  function setGuardian(address g) external onlyOwner {
    emit GuardianSet(guardian, g);
    guardian = g;
  }

  function setProtocolFeeBps(uint16 bps) external onlyOwner {
    if (bps > MAX_FEE_BPS) revert FeeAboveMax();
    protocolFeeBps = bps;
    emit ProtocolFeeSet(bps);
  }

  function setTVLCap(uint256 cap) external onlyOwner { tvlCap = cap; emit TVLCapSet(cap); }

  // ---- NGO management with 48h delay ----
  function queueCurrentNGO(address ngo) external onlyOwner {
    if (ngo == address(0)) revert InvalidParam();
    if (address(ngoRegistry) != address(0) && !ngoRegistry.isAllowed(ngo)) revert NGOForbidden();
    pendingNGO = ngo;
    pendingNGOEta = block.timestamp + NGO_SWITCH_DELAY;
    emit CurrentNGOSet(currentNGO, ngo, pendingNGOEta);
  }

  function switchCurrentNGO() external onlyOwner {
    if (pendingNGOEta == 0 || block.timestamp < pendingNGOEta) revert NGONotReady();
    address old = currentNGO;
    currentNGO = pendingNGO;
    pendingNGO = address(0);
    pendingNGOEta = 0;
    emit CurrentNGOSwitched(old, currentNGO);
  }

  // ---- Pausing (deposits only) ----
  function pauseDeposits(bool state) external onlyGuardianOrOwner {
    depositsPaused = state;
    emit DepositsPaused(state);
  }

  function _harvestWindowActive() internal view returns (bool) {
    return harvestWindowOpenBlock != 0 && block.number >= harvestWindowOpenBlock && block.number <= harvestWindowCloseBlock;
  }

  // ---- ERC-4626 Gating ----
  function deposit(uint256 assets, address receiver) public override(ERC4626Upgradeable) returns (uint256) {
    if (depositsPaused || _harvestWindowActive()) revert DepositsPausedErr();
    return super.deposit(assets, receiver);
  }

  function mint(uint256 shares, address receiver) public override(ERC4626Upgradeable) returns (uint256) {
    if (depositsPaused || _harvestWindowActive()) revert DepositsPausedErr();
    // Enforce TVL cap by converting shares to assets upper-bound
    uint256 assets = previewMint(shares);
    _checkCap(assets);
    return super.mint(shares, receiver);
  }

  function maxDeposit(address) public view override returns (uint256) {
    if (depositsPaused || _harvestWindowActive()) return 0;
    if (tvlCap == 0) return type(uint256).max;
    uint256 ta = totalAssets();
    return ta >= tvlCap ? 0 : (tvlCap - ta);
  }

  function _checkCap(uint256 depositAssets) internal view {
    if (tvlCap == 0) return;
    uint256 ta = totalAssets();
    require(ta + depositAssets <= tvlCap, "cap");
  }

  // Override to include adapter-held assets
  function totalAssets() public view override returns (uint256) {
    uint256 bal = IERC20(asset()).balanceOf(address(this));
    uint256 held = address(adapter) == address(0) ? 0 : ISimpleAdapter(adapter).totalAssets();
    return bal + held;
  }

  // Custom _deposit to move funds into adapter and track net inflow
  function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
    _checkCap(assets);
    IERC20 token = IERC20(asset());
    uint256 beforeBal = token.balanceOf(address(this));
    token.safeTransferFrom(caller, address(this), assets);
    uint256 received = token.balanceOf(address(this)) - beforeBal;
    if (received != assets) revert InvalidParam(); // reject fee-on-transfer/rebasing

    // Move to adapter custody
    if (address(adapter) != address(0) && received != 0) {
      SafeERC20.forceApprove(token, address(adapter), received);
      adapter.deposit(received);
      SafeERC20.forceApprove(token, address(adapter), 0);
    }

    inflowSinceLast += received;

    _mint(receiver, shares);
    emit Deposit(caller, receiver, assets, shares);
  }

  // Custom _withdraw to source assets from adapter and track outflow
  function _withdraw(
    address caller,
    address receiver,
    address owner_,
    uint256 assets,
    uint256 shares
  ) internal override {
    if (caller != owner_) {
      _spendAllowance(owner_, caller, shares);
    }

    // Pull assets from adapter if needed
    IERC20 token = IERC20(asset());
    uint256 bal = token.balanceOf(address(this));
    if (assets > bal) {
      uint256 toPull = assets - bal;
      if (address(adapter) != address(0) && toPull != 0) {
        adapter.withdraw(toPull, address(this));
      }
    }

    _burn(owner_, shares);
    token.safeTransfer(receiver, assets);
    outflowSinceLast += assets;
    emit Withdraw(caller, receiver, owner_, assets, shares);
  }

  // ---- Harvest ----
  function harvest(address ngo) external nonReentrant {
    if (ngo != currentNGO) revert NGOForbidden();

    uint256 ta = totalAssets();
    // Baseline = last + inflow - outflow
    uint256 baseline = assetsAtLastHarvest + inflowSinceLast;
    if (outflowSinceLast <= baseline) {
      baseline -= outflowSinceLast;
    } else {
      baseline = 0; // pathological, treat as zero to avoid underflow
    }

    uint256 harvested = ta > baseline ? ta - baseline : 0;
    if (harvested == 0) {
      // open short harvest window anyway to block sandwich deposits
      harvestWindowOpenBlock = block.number;
      harvestWindowCloseBlock = block.number + harvestWindowBlocks;
      return;
    }

    uint256 fee = (harvested * protocolFeeBps) / 10_000;
    uint256 remainder = harvested - fee;
    uint256 donated = (remainder * donationPercentBps) / 10_000;
    uint256 retained = remainder - donated;

    // Withdraw fee + donation to vault for transfers
    uint256 need = fee + donated;
    if (need != 0) {
      uint256 bal = IERC20(asset()).balanceOf(address(this));
      if (need > bal) {
        uint256 toPull = need - bal;
        if (address(adapter) != address(0) && toPull != 0) {
          adapter.withdraw(toPull, address(this));
        }
      }
    }

    // Pay fee
    if (fee != 0) {
      IERC20(asset()).safeTransfer(treasury, fee);
    }

    // Pay donation via DonationPayer (pull-based)
    if (donated != 0) {
      IERC20 token = IERC20(asset());
      SafeERC20.forceApprove(token, address(donationPayer), donated);
      donationPayer.donate(asset(), ngo, donated);
      SafeERC20.forceApprove(token, address(donationPayer), 0);
    }

    // Reset baseline and counters after outflows of fee and donation
    assetsAtLastHarvest = totalAssets();
    inflowSinceLast = 0;
    outflowSinceLast = 0;

    // Open brief harvest window (deposits/mints paused only)
    harvestWindowOpenBlock = block.number;
    harvestWindowCloseBlock = block.number + harvestWindowBlocks;

    emit Harvest(harvested, fee, donated, retained, ngo);
  }

  // ---- Emergency Unwind ----
  function emergencyUnwind(uint16 maxLossBps) external onlyGuardianOrOwner {
    if (maxLossBps > MAX_LOSS_BPS) revert InvalidParam();
    uint256 beforeTA = totalAssets();
    uint256 adapterBal = address(adapter) == address(0) ? 0 : adapter.totalAssets();
    if (adapterBal != 0) {
      adapter.emergencyUnwind(maxLossBps);
      // Pull all adapter assets back to vault
      adapterBal = adapter.totalAssets();
      if (adapterBal != 0) {
        adapter.withdraw(adapterBal, address(this));
      }
    }
    uint256 afterTA = totalAssets();
    // reset baseline around new position
    assetsAtLastHarvest = afterTA;
    inflowSinceLast = 0;
    outflowSinceLast = 0;
    emit EmergencyUnwind(maxLossBps, afterTA);
    // Note: realized loss bps can be computed off-chain from event and before/after snapshots.
  }
}
