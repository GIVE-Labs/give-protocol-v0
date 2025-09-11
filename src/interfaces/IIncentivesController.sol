// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IIncentivesController {
  event RewardsAccrued(address indexed user, uint256 amount);
  function handleAction(address user, uint256 userBalance, uint256 totalSupply) external;
}

