// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIncentivesController} from "../interfaces/IIncentivesController.sol";

/// @title GIVEToken (incentivized ERC-20 skeleton)
/// @notice ERC-20 with incentive hooks that notify IncentivesController on balance changes
abstract contract GIVEToken {
  string public name;
  string public symbol;
  uint8 public constant decimals = 18;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  IIncentivesController public incentivesController;

  event IncentivesControllerSet(address indexed oldController, address indexed newController);
  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);

  error AccessDenied();

  function setIncentivesController(address newController) external virtual;

  // ERC-20 surface to be implemented by concrete contract
  function transfer(address to, uint256 amount) external virtual returns (bool);
  function approve(address spender, uint256 amount) external virtual returns (bool);
  function transferFrom(address from, address to, uint256 amount) external virtual returns (bool);
  function mint(address to, uint256 amount) external virtual;
  function burn(address from, uint256 amount) external virtual;

  uint256[50] private __gap;
}
