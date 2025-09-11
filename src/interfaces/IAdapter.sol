// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAdapter {
  /// @notice Report harvested yield realized into the vault's asset
  /// @dev Only callable by the active adapter
  function reportHarvest(uint256 amount) external;
}

