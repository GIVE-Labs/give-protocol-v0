// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Treasury (storage skeleton)
/// @notice Receives protocol fees and manages POL
abstract contract Treasury {
  address public feeAsset; // donation asset / vault asset
  address public owner;

  event FeeReceived(address indexed asset, uint256 amount);
  event POLAdded(address indexed asset, uint256 amount, address indexed destination);
  event OwnerSet(address indexed oldOwner, address indexed newOwner);

  error AccessDenied();

  function setOwner(address newOwner) external virtual;
  function receiveFee(uint256 amount) external virtual;
  function addPOL(address asset, uint256 amount, address destination) external virtual;

  uint256[50] private __gap;
}

