// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {BoringVault4626} from "./BoringVault4626.sol";
import {EpochTypes} from "./EpochTypes.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";

/// @title GiveVault4626
/// @notice ERC-4626 vault with epoch-based accounting, Merkle-verified user yield claims, protocol fees, and a harvest window.
/// @dev
/// - Deposits/mints are paused briefly after a harvest (withdraw/redeem always available).
/// - Only the active strategy adapter (from StrategyManager) may call reportHarvest.
/// - Epoch roots are immutable once finalized and must satisfy conservation.
contract GiveVault4626 is ERC4626, BoringVault4626 {
  using SafeERC20 for ERC20;

  // External modules
  address public immutable strategyManager;
  address public treasury;

  // Config
  uint256 public harvestWindowBlocks; // number of blocks deposits/mints are paused after harvest

  // Accounting
  mapping(uint256 => uint256) private _epochHarvested; // epoch => harvested sum reported
  mapping(uint256 => uint256) private _epochFees; // epoch => fees sent to treasury
  mapping(uint256 => uint256) private _epochUserYieldClaimed; // epoch => claimed user yield sum

  // Local errors
  error InvalidParam();
  error FeeAboveMax();

  /// @notice Construct the GiveVault4626.
  /// @param asset_ The underlying ERC-20 asset of the vault (also the donation asset)
  /// @param name_ ERC-20 name for the share token
  /// @param symbol_ ERC-20 symbol for the share token
  /// @param strategyManager_ StrategyManager address controlling the active adapter
  /// @param treasury_ Treasury receiving protocol fees
  /// @param protocolFeeBps_ Protocol fee in basis points (<= MAX_FEE_BPS)
  /// @param harvestWindowBlocks_ Number of blocks to keep the harvest window open
  constructor(
    ERC20 asset_,
    string memory name_,
    string memory symbol_,
    address strategyManager_,
    address treasury_,
    uint16 protocolFeeBps_,
    uint256 harvestWindowBlocks_
  ) ERC20(name_, symbol_) ERC4626(asset_) {
    if (protocolFeeBps_ > MAX_FEE_BPS) revert FeeAboveMax();
    if (strategyManager_ == address(0) || treasury_ == address(0)) revert InvalidParam();
    strategyManager = strategyManager_;
    treasury = treasury_;
    protocolFeeBps = protocolFeeBps_;
    harvestWindowBlocks = harvestWindowBlocks_;

    // Start at epoch 0; first call to rollEpoch closes 0 and opens 1 (emits 0)
    currentEpoch = 0;
  }

  // -------------------------
  // ERC-4626 deposit/mint gating during harvest window
  // -------------------------
  function deposit(uint256 assets, address receiver) public override returns (uint256) {
    if (_harvestWindowActive()) revert HarvestWindowOpen();
    return super.deposit(assets, receiver);
  }

  function mint(uint256 shares, address receiver) public override returns (uint256) {
    if (_harvestWindowActive()) revert HarvestWindowOpen();
    return super.mint(shares, receiver);
  }

  function _harvestWindowActive() internal view returns (bool) {
    // Active if current block is within [open, close]
    return harvestWindowOpenBlock != 0 &&
      block.number >= harvestWindowOpenBlock &&
      block.number <= harvestWindowCloseBlock;
  }

  // -------------------------
  // Epoch lifecycle
  // -------------------------
  /// @notice Closes the current epoch and opens the next one (permissionless).
  function rollEpoch() external override {
    // Closes currentEpoch and opens next; permissionless
    emit EpochRolled(currentEpoch);
    currentEpoch += 1;
  }

  // -------------------------
  // Harvest reporting
  // -------------------------
  /// @notice Report realized yield in the underlying asset for the current epoch; charges protocol fee immediately.
  /// @param harvested Amount of underlying realized for the vault this epoch
  function reportHarvest(uint256 harvested) external override {
    // Only active adapter may report
    if (IStrategyManager(strategyManager).activeAdapter() != msg.sender) revert OnlyActiveAdapter();
    if (harvested == 0) return;

    uint256 fee = (harvested * protocolFeeBps) / 10_000;
    _epochHarvested[currentEpoch] += harvested;
    if (fee != 0) {
      _epochFees[currentEpoch] += fee;
      // Transfer fee to treasury immediately ("before split")
      ERC20(address(asset())).safeTransfer(treasury, fee);
      emit FeeCollected(currentEpoch, fee);
    }

    // Open a brief harvest window where deposits/mints are paused
    harvestWindowOpenBlock = block.number;
    harvestWindowCloseBlock = block.number + harvestWindowBlocks;

    emit HarvestReported(currentEpoch, harvested);
  }

  // -------------------------
  // Merkle root finalize for closed epochs
  // -------------------------
  /// @notice Finalize the immutable Merkle root for a closed epoch with its totals; enforces conservation and cross-checks counters.
  /// @param epoch The epoch index being finalized (must be < currentEpoch)
  /// @param root The Merkle root covering user yield claims for this epoch
  /// @param totals Struct with harvested, fee, donationTotal, userYieldTotal; must satisfy conservation and match counters
  function finalizeEpochRoot(
    uint256 epoch,
    bytes32 root,
    EpochTypes.EpochTotals calldata totals
  ) external override {
    if (_epochRoot[epoch] != bytes32(0)) revert RootAlreadyFinalized();
    // Can only finalize for closed epochs (epoch < currentEpoch)
    require(epoch < currentEpoch, "epoch not closed");

    // Conservation: harvested == fee + donation + userYield
    if (totals.harvested != totals.fee + totals.donationTotal + totals.userYieldTotal) revert InvalidParam();

    // Cross-check against on-chain counters
    require(totals.harvested == _epochHarvested[epoch], "harvest mismatch");
    require(totals.fee == _epochFees[epoch], "fee mismatch");

    _epochRoot[epoch] = root;
    _epochTotals[epoch] = totals;
    emit EpochRootFinalized(epoch, root, totals);
  }

  // -------------------------
  // Donation share management
  // -------------------------
  /// @notice Set the caller's donation share bps for future epochs; only {5000, 7500, 10000} are allowed.
  /// @param bps Donation share in basis points; becomes effective next epoch
  function setDonationShareBps(uint16 bps) external override {
    if (bps != 5000 && bps != 7500 && bps != 10_000) revert InvalidDonationShare();
    uint256 effectiveEpoch = currentEpoch + 1; // next epoch
    _pendingDonationShareBps[msg.sender] = bps;
    _pendingDonationShareEffectiveEpoch[msg.sender] = effectiveEpoch;
    emit DonationShareSet(msg.sender, bps, effectiveEpoch);
  }

  // -------------------------
  // User yield claim (Merkle-verified)
  // -------------------------
  /// @notice Claim user-proportional yield for a given epoch using a Merkle proof; single-claim per user/epoch enforced via bitmap.
  /// @param epoch The epoch index
  /// @param amount The amount encoded in the user's Merkle leaf for this epoch
  /// @param proof Merkle proof of inclusion for leaf keccak256(user, amount)
  function claimUserYield(uint256 epoch, uint256 amount, bytes32[] calldata proof) external override {
    bytes32 root = _epochRoot[epoch];
    if (root == bytes32(0)) revert InvalidMerkleProof();

    // Bitmap: word = epoch / 256, bit = epoch % 256
    uint256 wordIndex = epoch >> 8; // /256
    uint256 bitMask = uint256(1) << (epoch & 255);
    uint256 word = _claimBitmap[msg.sender][wordIndex];
    if (word & bitMask != 0) revert AlreadyClaimed();

    // Verify proof for leaf = keccak256(user, amount)
    bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
    if (!MerkleProof.verifyCalldata(proof, root, leaf)) revert InvalidMerkleProof();

    // Bounds vs totals
    EpochTypes.EpochTotals memory totals = _epochTotals[epoch];
    uint256 claimedSoFar = _epochUserYieldClaimed[epoch];
    require(claimedSoFar + amount <= totals.userYieldTotal, "exceeds user total");

    // Mark claimed
    _claimBitmap[msg.sender][wordIndex] = word | bitMask;
    _epochUserYieldClaimed[epoch] = claimedSoFar + amount;

    // Transfer assets to user
    ERC20(address(asset())).safeTransfer(msg.sender, amount);
    emit UserYieldClaimed(msg.sender, epoch, amount);
  }

  // -------------------------
  // Views
  // -------------------------
  /// @notice Returns the donation asset (same as vault asset)
  function donationAsset() external view override returns (address) {
    return asset();
  }

  /// @notice Returns the donation total recorded for a given epoch
  /// @param epoch The epoch index
  function donationAmountForEpoch(uint256 epoch) external view override returns (uint256) {
    return _epochTotals[epoch].donationTotal;
  }

  /// @notice Returns the Merkle root finalized for a given epoch (zero if not finalized)
  /// @param epoch The epoch index
  function epochRoot(uint256 epoch) external view override returns (bytes32) {
    return _epochRoot[epoch];
  }
}
