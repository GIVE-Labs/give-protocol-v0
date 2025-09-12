// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title NGORegistrySimple
/// @notice Minimal allowlist with 2-step add (48h delay) and immediate revoke.
contract NGORegistrySimple is AccessControl {
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  uint256 public constant ADD_DELAY = 48 hours;

  mapping(address => bool) public isAllowed;
  mapping(address => uint256) public addEta;

  event NGOAnnounced(address indexed ngo, uint256 eta);
  event NGOAdded(address indexed ngo);
  event NGORevoked(address indexed ngo);

  error NotQueued();
  error TooSoon();

  constructor(address admin, address manager) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MANAGER_ROLE, manager);
  }

  function announceAdd(address ngo) external onlyRole(MANAGER_ROLE) {
    uint256 eta = block.timestamp + ADD_DELAY;
    addEta[ngo] = eta;
    emit NGOAnnounced(ngo, eta);
  }

  function add(address ngo) external onlyRole(MANAGER_ROLE) {
    uint256 eta = addEta[ngo];
    if (eta == 0) revert NotQueued();
    if (block.timestamp < eta) revert TooSoon();
    addEta[ngo] = 0;
    isAllowed[ngo] = true;
    emit NGOAdded(ngo);
  }

  function revoke(address ngo) external onlyRole(MANAGER_ROLE) {
    if (isAllowed[ngo]) {
      isAllowed[ngo] = false;
      emit NGORevoked(ngo);
    }
  }
}

