// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title NGORegistry
/// @notice Minimal allowlist with two-step add (timelocked), normal revoke (via external timelock), and emergency revoke (0 delay).
/// @dev Tracks membership timestamps to gate eligibility at specific settlement times for the DonationRouter.
contract NGORegistry is AccessControl {
  bytes32 public constant NGO_MANAGER_ROLE = keccak256("NGO_MANAGER_ROLE");

  mapping(address => bool) public isAllowed;
  mapping(address => uint256) public addEta; // queued add timestamp
  mapping(address => uint256) public addedAt; // activation timestamp
  mapping(address => uint256) public revokedAt; // 0 if active, else timestamp when revoked

  uint256 public constant ADD_DELAY = 365 days; // 1 year
  // Normal revoke delay (6m) should be enforced by external timelock; stored here for reference only.
  uint256 public constant REVOKE_DELAY = 180 days; // 6 months

  uint256 public allowedCount; // number of active NGOs

  event NGOAddQueued(address indexed ngo, uint256 eta);
  event NGOAdded(address indexed ngo);
  event NGORevoked(address indexed ngo, bool emergency);

  error NotQueued();
  error TooSoon();

  constructor(address admin, address manager) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(NGO_MANAGER_ROLE, manager);
  }

  /// @notice Queue an NGO for allowlist addition. Must be finalized after ADD_DELAY.
  /// @param ngo The NGO address to add
  function queueAdd(address ngo) external onlyRole(NGO_MANAGER_ROLE) {
    uint256 eta = block.timestamp + ADD_DELAY;
    addEta[ngo] = eta;
    emit NGOAddQueued(ngo, eta);
  }

  /// @notice Finalize a previously queued NGO addition after ADD_DELAY has elapsed.
  /// @param ngo The NGO address
  function finalizeAdd(address ngo) external onlyRole(NGO_MANAGER_ROLE) {
    uint256 eta = addEta[ngo];
    if (eta == 0) revert NotQueued();
    if (block.timestamp < eta) revert TooSoon();
    addEta[ngo] = 0;
    if (!isAllowed[ngo]) {
      isAllowed[ngo] = true;
      addedAt[ngo] = block.timestamp;
      revokedAt[ngo] = 0;
      allowedCount += 1;
    }
    emit NGOAdded(ngo);
  }

  // Normal revoke (6m) — delay expected via external Timelock; immediate here when called.
  /// @notice Normal revoke (6m expected via external timelock). Immediately flips allowlist and records revokedAt.
  /// @param ngo The NGO address to revoke
  function revoke(address ngo) external onlyRole(NGO_MANAGER_ROLE) {
    if (isAllowed[ngo]) {
      isAllowed[ngo] = false;
      revokedAt[ngo] = block.timestamp;
      if (allowedCount > 0) allowedCount -= 1;
      emit NGORevoked(ngo, false);
    }
  }

  // Emergency revoke — immediate; blocks future payouts only.
  /// @notice Emergency revoke; immediate and blocks future payouts only.
  /// @param ngo The NGO address to revoke
  function emergencyRevoke(address ngo) external onlyRole(NGO_MANAGER_ROLE) {
    if (isAllowed[ngo]) {
      isAllowed[ngo] = false;
      revokedAt[ngo] = block.timestamp;
      if (allowedCount > 0) allowedCount -= 1;
      emit NGORevoked(ngo, true);
    }
  }

  // View helper: was `ngo` eligible at timestamp `ts`?
  /// @notice Returns whether `ngo` was eligible at timestamp `ts`.
  /// @param ngo The NGO address
  /// @param ts The timestamp to evaluate eligibility at
  /// @dev `ts <= revokedAt` is considered eligible to avoid impacting already-settled epochs.
  function isEligibleAt(address ngo, uint256 ts) external view returns (bool) {
    uint256 addTs = addedAt[ngo];
    if (addTs == 0 || ts < addTs) return false;
    uint256 revTs = revokedAt[ngo];
    // Treat equality as eligible so that epochs settled just before (or within the same timestamp as)
    // a revoke remain payable. Future epochs settled strictly after a revoke are ineligible.
    return revTs == 0 || ts <= revTs;
  }
}
