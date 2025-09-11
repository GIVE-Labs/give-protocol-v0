// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Proxy (skeleton)
/// @notice Placeholder for UUPS or Transparent proxy wrapper usage (prefer OZ proxies)
abstract contract Proxy {
  address public implementation;
  address public admin;

  event Upgraded(address indexed newImplementation);
  event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

  function upgradeTo(address newImplementation) external virtual;
  function changeAdmin(address newAdmin) external virtual;

  uint256[50] private __gap;
}

