// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISimpleAdapter {
  function asset() external view returns (address);
  function vault() external view returns (address);

  function totalAssets() external view returns (uint256);

  // Pull assets from vault into adapter custody
  function deposit(uint256 assets) external;

  // Push assets from adapter to `to`
  function withdraw(uint256 assets, address to) external;

  // Realize assets back to underlying, bounded by maxLossBps
  function emergencyUnwind(uint16 maxLossBps) external returns (uint256 realizedAssets);
}

