// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDonationRouter {
  event DonationCredited(address indexed ngo, uint256 indexed epoch, uint256 amount);
  event NGOClaim(address indexed ngo, address indexed to, uint256 amount);
  event EpochSettled(uint256 indexed epoch, uint256 creditedTotal);

  function settleEpoch(uint256 epoch) external;
  function claim(address ngo, address to) external returns (uint256);
}

