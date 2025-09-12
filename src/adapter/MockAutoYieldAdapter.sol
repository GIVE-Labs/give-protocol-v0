// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISimpleAdapter} from "../interfaces/ISimpleAdapter.sol";

interface IMockMintable {
  function mint(address to, uint256 amount) external;
}

/// @title MockAutoYieldAdapter
/// @notice Testing adapter that simulates venue yield over time by virtually accruing, and minting on state changes.
/// @dev Requires the `asset` to be a mintable mock (e.g., MockERC20Decimals) when running locally.
contract MockAutoYieldAdapter is ISimpleAdapter {
  using SafeERC20 for IERC20;

  address public immutable override asset;
  address public override vault;

  uint256 public principal; // net underlying supplied
  uint256 public lastAccrue; // last timestamp we minted accrued yield
  uint256 public ratePerSecondWad; // 1e18 precision per-second rate (e.g., ~1e9 ~= 3.15% APR)

  event Deposited(uint256 assets);
  event Withdrawn(uint256 assets, address indexed to);
  event EmergencyUnwind(uint16 maxLossBps, uint256 realizedAssets);
  event VaultSet(address indexed vault);
  event Accrued(uint256 minted, uint256 principal, uint256 timestamp);

  error OnlyVault();

  constructor(address asset_, address vault_, uint256 ratePerSecondWad_) {
    require(asset_ != address(0), "zero");
    asset = asset_;
    vault = vault_;
    ratePerSecondWad = ratePerSecondWad_;
    lastAccrue = block.timestamp;
  }

  modifier onlyVault() { if (msg.sender != vault) revert OnlyVault(); _; }

  function setVault(address newVault) external {
    require(vault == address(0) && newVault != address(0), "set");
    vault = newVault;
    emit VaultSet(newVault);
  }

  function _pendingYield() internal view returns (uint256) {
    if (ratePerSecondWad == 0 || principal == 0) return 0;
    uint256 dt = block.timestamp - lastAccrue;
    if (dt == 0) return 0;
    // simple linear accrual: principal * rate * dt / 1e18
    return (principal * ratePerSecondWad * dt) / 1e18;
  }

  function _accrue() internal {
    uint256 mintAmt = _pendingYield();
    if (mintAmt != 0) {
      IMockMintable(asset).mint(address(this), mintAmt);
      emit Accrued(mintAmt, principal, block.timestamp);
    }
    lastAccrue = block.timestamp;
  }

  function totalAssets() external view override returns (uint256) {
    // report on-chain balance plus virtual yield since last accrue
    return IERC20(asset).balanceOf(address(this)) + _pendingYield();
  }

  function deposit(uint256 assets) external override onlyVault {
    if (assets == 0) return;
    _accrue();
    // pull from vault and increase principal
    IERC20(asset).safeTransferFrom(vault, address(this), assets);
    principal += assets;
    emit Deposited(assets);
  }

  function withdraw(uint256 assets, address to) external override onlyVault {
    if (assets == 0) return;
    _accrue();
    // transfer underlying out; principal reduced up to available principal portion
    IERC20(asset).safeTransfer(to, assets);
    // reduce principal by min(assets, principal) to avoid underflow
    uint256 p = principal;
    principal = assets >= p ? 0 : (p - assets);
    emit Withdrawn(assets, to);
  }

  function emergencyUnwind(uint16 maxLossBps) external override onlyVault returns (uint256 realizedAssets) {
    _accrue();
    realizedAssets = IERC20(asset).balanceOf(address(this));
    if (realizedAssets != 0) {
      IERC20(asset).safeTransfer(vault, realizedAssets);
    }
    principal = 0;
    emit EmergencyUnwind(maxLossBps, realizedAssets);
  }
}

