// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IBoringVault4626} from "../interfaces/IBoringVault4626.sol";

interface INGORegistry {
  function allowedCount() external view returns (uint256);
  function isEligibleAt(address ngo, uint256 ts) external view returns (bool);
  function isAllowed(address ngo) external view returns (bool);
}

/// @title DonationRouter
/// @notice Pull-based NGO claims. Reads vault donation totals, snapshots NGO count at settlement, and lets NGOs claim pro-rata.
/// @dev
/// - Settlement snapshots donation totals and eligible NGO count.
/// - Claims iterate settled epochs since the NGO's cursor, gating eligibility at settlement time.
/// - Router pulls tokens from the vault's balance (vault must approve this router for donationAsset).
contract DonationRouter is ReentrancyGuard, AccessControl {
  using SafeERC20 for IERC20;

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  IBoringVault4626 public immutable boringVault;
  INGORegistry public ngoRegistry;

  // epoch => settled?
  mapping(uint256 => bool) public epochSettled;
  // epoch => donation total snapshot
  mapping(uint256 => uint256) public epochDonation;
  // epoch => NGO count snapshot
  mapping(uint256 => uint256) public epochNgoCount;
  // epoch => settlement timestamp
  mapping(uint256 => uint256) public epochSettleTs;

  // NGO claim cursor: next epoch index to include
  mapping(address => uint256) public ngoClaimCursor;

  uint256 public lastSettledEpoch;

  event DonationCredited(address indexed ngo, uint256 indexed epoch, uint256 amount);
  event NGOClaim(address indexed ngo, address indexed to, uint256 amount);
  event EpochSettled(uint256 indexed epoch, uint256 creditedTotal);
  event NGORegistrySet(address indexed oldRegistry, address indexed newRegistry);

  error AlreadySettled();

  /// @param vault The GiveProtocol vault exposing donation views
  /// @param registry The NGO registry contract
  /// @param admin Admin for access-controlled functions (e.g., setRegistry)
  constructor(address vault, address registry, address admin) {
    boringVault = IBoringVault4626(vault);
    ngoRegistry = INGORegistry(registry);
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(ADMIN_ROLE, admin);
  }

  /// @notice Update the NGO registry address.
  /// @param registry The new registry address
  function setRegistry(address registry) external onlyRole(ADMIN_ROLE) {
    address old = address(ngoRegistry);
    ngoRegistry = INGORegistry(registry);
    emit NGORegistrySet(old, registry);
  }

  // Permissionless settlement: snapshots donation totals and NGO count for an epoch after the vault finalizes root.
  /// @notice Permissionless settlement of an epoch; snapshots totals and NGO count.
  /// @param epoch The epoch index to settle; requires a non-zero Merkle root in the vault
  function settleEpoch(uint256 epoch) external {
    if (epochSettled[epoch]) revert AlreadySettled();
    // Require vault has finalized root for this epoch (non-zero root)
    require(boringVault.epochRoot(epoch) != bytes32(0), "root not finalized");
    uint256 amount = boringVault.donationAmountForEpoch(epoch);
    epochDonation[epoch] = amount;
    uint256 count = ngoRegistry.allowedCount();
    epochNgoCount[epoch] = count;
    epochSettleTs[epoch] = block.timestamp;
    epochSettled[epoch] = true;
    if (epoch > lastSettledEpoch) lastSettledEpoch = epoch;
    emit EpochSettled(epoch, amount);
  }

  // NGOs claim their pro-rata share across all settled epochs since their last claim.
  /// @notice Claim accumulated pro-rata donation amounts across settled epochs since the NGO's last claim.
  /// @param ngo The NGO address claiming
  /// @param to Recipient address for funds
  /// @return total The total amount transferred to `to`
  function claim(address ngo, address to) external nonReentrant returns (uint256) {
    require(ngo != address(0) && to != address(0), "zero addr");

    uint256 from = ngoClaimCursor[ngo];
    if (from == 0) {
      // Start from epoch 0 by default
      from = 0;
    }
    uint256 toEpoch = lastSettledEpoch;

    uint256 total;
    for (uint256 e = from; e <= toEpoch; ++e) {
      if (!epochSettled[e]) continue;
      uint256 count = epochNgoCount[e];
      if (count == 0) continue;
      // NGO must have been eligible at settlement time
      if (!ngoRegistry.isEligibleAt(ngo, epochSettleTs[e])) continue;
      uint256 share = epochDonation[e] / count;
      total += share;
    }

    // Advance cursor to after last settled epoch
    ngoClaimCursor[ngo] = toEpoch + 1;

    if (total > 0) {
      IERC20 token = IERC20(boringVault.donationAsset());
      // Pull from vault: requires prior allowance set for this router on the vault's token balance
      token.safeTransferFrom(address(boringVault), to, total);
      emit NGOClaim(ngo, to, total);
    }
    return total;
  }

  /// @notice Returns the donation ERC-20 asset address (vault asset)
  function donationAsset() external view returns (address) {
    return boringVault.donationAsset();
  }

  // View helper for tests/UX: compute pending claim amount for an NGO across settled epochs
  /// @notice View helper: compute pending claim amount for an NGO across settled epochs.
  /// @param ngo The NGO address to query
  /// @return total Accumulated amount
  /// @return from Cursor epoch index used
  /// @return toEpoch Last settled epoch index considered
  function pendingAmount(address ngo) external view returns (uint256 total, uint256 from, uint256 toEpoch) {
    from = ngoClaimCursor[ngo];
    toEpoch = lastSettledEpoch;
    for (uint256 e = from; e <= toEpoch; ++e) {
      if (!epochSettled[e]) continue;
      uint256 count = epochNgoCount[e];
      if (count == 0) continue;
      if (!ngoRegistry.isEligibleAt(ngo, epochSettleTs[e])) continue;
      total += epochDonation[e] / count;
      if (e == type(uint256).max) break; // safety
    }
  }
}
