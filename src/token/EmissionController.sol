// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title EmissionController (skeleton)
/// @notice Controls emissions schedule for staking/incentives
abstract contract EmissionController {
  address public owner;

  event OwnerSet(address indexed oldOwner, address indexed newOwner);
  event EmissionRateSet(uint256 newRate);

  error AccessDenied();

  function setOwner(address newOwner) external virtual;
  function setEmissionRate(uint256 newRate) external virtual;

  uint256[50] private __gap;
}

