// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ACLManager
/// @notice Role registry for Give Protocol; storage + events only (no business logic)
abstract contract ACLManager {
  // Roles
  bytes32 public constant ADMIN = keccak256("ADMIN");
  bytes32 public constant UPGRADER = keccak256("UPGRADER");
  bytes32 public constant NGO_MANAGER = keccak256("NGO_MANAGER");
  bytes32 public constant STRATEGY_MANAGER = keccak256("STRATEGY_MANAGER");
  bytes32 public constant ORACLE_MANAGER = keccak256("ORACLE_MANAGER");
  bytes32 public constant TREASURY = keccak256("TREASURY");
  bytes32 public constant PAUSER = keccak256("PAUSER");
  bytes32 public constant KEEPER = keccak256("KEEPER");

  // Storage
  mapping(address => mapping(bytes32 => bool)) internal _roles; // account => role => has
  address internal _adminMultisig;

  // Events
  event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
  event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
  event AdminMultisigSet(address indexed oldAdmin, address indexed newAdmin);

  // Errors
  error AccessDenied();

  // Views (to be implemented by concrete contract)
  function hasRole(bytes32 role, address account) public view virtual returns (bool);

  // Mutations (to be implemented by concrete contract)
  function grantRole(bytes32 role, address account) external virtual;
  function revokeRole(bytes32 role, address account) external virtual;
  function setAdminMultisig(address admin) external virtual;

  // Storage gap for upgrades
  uint256[50] private __gap;
}

