// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISimpleAdapter} from "../interfaces/ISimpleAdapter.sol";

/// @notice Minimal subset of Aave V3 Pool interface
interface IAaveV3Pool {
  function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
  function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/// @title SimpleAaveAdapter
/// @notice Minimal adapter for Aave V3.1. Holds aTokens and exposes totalAssets.
/// @dev Vault must approve adapter to pull `asset` on deposit. `aToken` is passed at construction.
contract SimpleAaveAdapter is ISimpleAdapter {
  using SafeERC20 for IERC20;

  address public immutable override asset;
  address public override vault;
  address public immutable aToken;
  IAaveV3Pool public immutable pool;

  event Deposited(uint256 assets);
  event Withdrawn(uint256 assets, address indexed to);
  event EmergencyUnwind(uint16 maxLossBps, uint256 realizedAssets);
  error OnlyVault();

  constructor(address asset_, address aToken_, address pool_, address vault_) {
    require(asset_ != address(0) && aToken_ != address(0) && pool_ != address(0), "zero");
    asset = asset_;
    aToken = aToken_;
    pool = IAaveV3Pool(pool_);
    vault = vault_;
  }

  modifier onlyVault() { if (msg.sender != vault) revert OnlyVault(); _; }

  function setVault(address newVault) external {
    require(vault == address(0) && newVault != address(0), "set");
    vault = newVault;
  }

  function totalAssets() external view override returns (uint256) {
    return IERC20(aToken).balanceOf(address(this));
  }

  function deposit(uint256 assets) external override onlyVault {
    if (assets == 0) return;
    IERC20 token = IERC20(asset);
    token.safeTransferFrom(vault, address(this), assets);
    SafeERC20.forceApprove(token, address(pool), assets);
    pool.supply(asset, assets, address(this), 0);
    SafeERC20.forceApprove(token, address(pool), 0);
    emit Deposited(assets);
  }

  function withdraw(uint256 assets, address to) external override onlyVault {
    if (assets == 0) return;
    pool.withdraw(asset, assets, to);
    emit Withdrawn(assets, to);
  }

  function emergencyUnwind(uint16 maxLossBps) external override onlyVault returns (uint256 realizedAssets) {
    uint256 bal = IERC20(aToken).balanceOf(address(this));
    if (bal == 0) return 0;
    // Withdraw all to vault
    realizedAssets = pool.withdraw(asset, type(uint256).max, vault);
    emit EmergencyUnwind(maxLossBps, realizedAssets);
  }
}

