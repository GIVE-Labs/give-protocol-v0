// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal target exposing ERC-4626-like signatures for testing the manager decoders
contract MockERC4626Target {
  event Deposit(address indexed caller, uint256 assets, address indexed receiver);
  event Withdraw(address indexed caller, uint256 assets, address indexed receiver, address indexed owner);

  address public lastReceiver;
  address public lastOwner;
  uint256 public lastAssets;

  function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
    lastAssets = assets;
    lastReceiver = receiver;
    emit Deposit(msg.sender, assets, receiver);
    return assets; // 1:1 for test
  }

  function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
    lastAssets = assets;
    lastReceiver = receiver;
    lastOwner = owner;
    emit Withdraw(msg.sender, assets, receiver, owner);
    return assets;
  }
}

