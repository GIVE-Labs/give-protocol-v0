// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIncentivesController} from "../interfaces/IIncentivesController.sol";

/// @title IncentivesController (skeleton)
/// @notice Accrues rewards on balance changes (Aave-style hook surface)
abstract contract IncentivesController is IIncentivesController {
  mapping(address => uint256) public accruedRewards;
  address public emissionController;

  event EmissionControllerSet(address indexed oldController, address indexed newController);

  function handleAction(address user, uint256 userBalance, uint256 totalSupply) external virtual override;
  function claimRewards(address user, address to) external virtual returns (uint256);

  uint256[50] private __gap;
}

