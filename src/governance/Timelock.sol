// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Timelock (storage skeleton)
/// @notice Enforces delays for upgrades, risk params, MAX_FEE_BPS, template changes, NGO add/remove
abstract contract Timelock {
  uint256 public constant DELAY_UPGRADES = 365 days; // 1y
  uint256 public constant DELAY_RISK = 180 days;     // 6m
  uint256 public constant DELAY_LONG = 730 days;     // 2y

  struct Operation {
    address target;
    bytes data;
    uint256 value;
    uint256 eta;
    bool executed;
    bool cancelled;
  }

  mapping(bytes32 => Operation) public ops; // opId => op

  event Queued(bytes32 indexed id, address indexed target, uint256 value, uint256 eta);
  event Executed(bytes32 indexed id);
  event Cancelled(bytes32 indexed id);

  error NotReady();
  error AlreadyExecuted();
  error AlreadyQueued();

  function queue(address target, uint256 value, bytes calldata data, uint256 eta, bytes32 salt)
    external
    virtual
    returns (bytes32 id);
  function execute(bytes32 id) external payable virtual;
  function cancel(bytes32 id) external virtual;

  uint256[50] private __gap;
}

