// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStrategyManager {
  event ActiveAdapterSet(address indexed oldAdapter, address indexed newAdapter);
  event CapsSet(uint256 tvlCap, uint16 maxExposureBps);

  function setActiveAdapter(address adapter) external;
  function setCaps(uint256 tvlCap, uint16 maxExposureBps) external;
  function activeAdapter() external view returns (address);
}

