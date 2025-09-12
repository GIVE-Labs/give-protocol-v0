// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISimpleAdapter} from "../interfaces/ISimpleAdapter.sol";

/// @title SimpleHoldingAdapter
/// @notice Minimal adapter that simply holds the underlying asset. Used for MVP/testing.
/// @dev Vault must approve exact amounts for deposit; adapter pulls from vault and holds tokens.
contract SimpleHoldingAdapter is ISimpleAdapter {
  using SafeERC20 for IERC20;

  address public immutable override asset;
  address public override vault;

  event Deposited(uint256 assets);
  event Withdrawn(uint256 assets, address indexed to);
  event EmergencyUnwind(uint16 maxLossBps, uint256 realizedAssets);

  error OnlyVault();

  constructor(address asset_, address vault_) {
    require(asset_ != address(0), "zero");
    asset = asset_;
    vault = vault_;
  }

  function setVault(address newVault) external {
    require(vault == address(0) && newVault != address(0), "set");
    vault = newVault;
  }

  modifier onlyVault() { if (msg.sender != vault) revert OnlyVault(); _; }

  function totalAssets() external view override returns (uint256) {
    return IERC20(asset).balanceOf(address(this));
  }

  function deposit(uint256 assets) external override onlyVault {
    if (assets == 0) return;
    IERC20(asset).safeTransferFrom(vault, address(this), assets);
    emit Deposited(assets);
  }

  function withdraw(uint256 assets, address to) external override onlyVault {
    if (assets == 0) return;
    IERC20(asset).safeTransfer(to, assets);
    emit Withdrawn(assets, to);
  }

  function emergencyUnwind(uint16 maxLossBps) external override onlyVault returns (uint256 realizedAssets) {
    // Holding adapter has nothing to unwind; just report current balance.
    realizedAssets = IERC20(asset).balanceOf(address(this));
    emit EmergencyUnwind(maxLossBps, realizedAssets);
  }
}
