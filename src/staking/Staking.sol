// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Staking (skeleton)
/// @notice Staking of vault shares; optional milestone
abstract contract Staking {
  address public vault; // vault share token
  address public rewardsToken; // GIVE or other

  event Staked(address indexed user, uint256 amount);
  event Unstaked(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 amount);

  function stake(uint256 amount) external virtual;
  function unstake(uint256 amount) external virtual;
  function getReward() external virtual;

  uint256[50] private __gap;
}

