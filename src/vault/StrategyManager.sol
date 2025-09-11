// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title StrategyManager
/// @notice Enforces a single active strategy adapter, TVL/exposure caps, and a 6-month rotation timelock.
/// @dev Uses OpenZeppelin AccessControl. The strategist role schedules a new adapter, then after delay sets it active.
contract StrategyManager is IStrategyManager, AccessControl {
  // Roles
  bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");

  // Active adapter
  address internal _activeAdapter;

  // Risk parameters
  uint256 public tvlCap; // total vault TVL cap
  uint16 public maxExposureBps; // per-asset exposure cap (0..10000)

  // Rotation timelock (6 months)
  uint256 public constant ROTATION_DELAY = 180 days;
  address public pendingAdapter;
  uint256 public pendingAdapterEta;

  // Additional events
  event AdapterRotationScheduled(address indexed newAdapter, uint256 eta);
  event AdapterRotationCancelled(address indexed newAdapter);

  // Errors
  error RotationNotReady();
  error InvalidAdapter();

  constructor(address admin, address strategyManager) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(STRATEGY_MANAGER_ROLE, strategyManager);
  }

  /// @notice Schedule rotation to a new adapter; after delay, call setActiveAdapter(newAdapter).
  /// @param adapter The address of the adapter to activate after delay
  function scheduleActiveAdapter(address adapter) external onlyRole(STRATEGY_MANAGER_ROLE) {
    if (adapter == address(0)) revert InvalidAdapter();
    pendingAdapter = adapter;
    pendingAdapterEta = block.timestamp + ROTATION_DELAY;
    emit AdapterRotationScheduled(adapter, pendingAdapterEta);
  }

  /// @notice Cancel a previously scheduled adapter rotation.
  function cancelActiveAdapterRotation() external onlyRole(STRATEGY_MANAGER_ROLE) {
    address adapter = pendingAdapter;
    pendingAdapter = address(0);
    pendingAdapterEta = 0;
    emit AdapterRotationCancelled(adapter);
  }

  /// @notice Set the active adapter after the rotation delay has elapsed for the scheduled adapter.
  /// @param adapter The adapter that was previously scheduled
  function setActiveAdapter(address adapter) external override onlyRole(STRATEGY_MANAGER_ROLE) {
    if (adapter != pendingAdapter || block.timestamp < pendingAdapterEta) revert RotationNotReady();
    address old = _activeAdapter;
    _activeAdapter = adapter;
    pendingAdapter = address(0);
    pendingAdapterEta = 0;
    emit ActiveAdapterSet(old, adapter);
  }

  /// @notice Set TVL cap and per-asset exposure cap in basis points.
  /// @param _tvlCap Maximum aggregate TVL for the vault
  /// @param _maxExposureBps Maximum exposure per asset (0..10000)
  function setCaps(uint256 _tvlCap, uint16 _maxExposureBps) external override onlyRole(STRATEGY_MANAGER_ROLE) {
    if (_maxExposureBps > 10_000) revert();
    tvlCap = _tvlCap;
    maxExposureBps = _maxExposureBps;
    emit CapsSet(_tvlCap, _maxExposureBps);
  }

  /// @notice Returns the currently active adapter address.
  function activeAdapter() external view override returns (address) {
    return _activeAdapter;
  }
}
