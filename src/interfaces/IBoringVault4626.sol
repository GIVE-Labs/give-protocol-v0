// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EpochTypes} from "../vault/EpochTypes.sol";

/// @title IBoringVault4626
/// @notice ERC-4626 superset for the Give Protocol vault
interface IBoringVault4626 {
  // Core epoch/yield events
  event HarvestReported(uint256 indexed epoch, uint256 amount);
  event EpochRolled(uint256 indexed epoch);
  event EpochRootFinalized(uint256 indexed epoch, bytes32 root, EpochTypes.EpochTotals totals);
  event DonationShareSet(address indexed user, uint16 bps, uint256 effectiveEpoch);
  event UserYieldClaimed(address indexed user, uint256 indexed epoch, uint256 amount);
  event FeeCollected(uint256 indexed epoch, uint256 amount);

  // Epoch lifecycle
  function rollEpoch() external;
  /// @notice Report realized yield for the current epoch; only the active adapter may call.
  /// @param harvested Amount of underlying realized by the active adapter
  function reportHarvest(uint256 harvested) external;
  /// @notice Finalize the Merkle root and totals for a closed epoch (immutable once set).
  /// @param epoch The epoch index being finalized (must be < currentEpoch)
  /// @param root The Merkle root for user yield claims
  /// @param totals The harvested/fee/donation/userYield totals for conservation
  function finalizeEpochRoot(uint256 epoch, bytes32 root, EpochTypes.EpochTotals calldata totals) external;

  // Donation share management
  /// @notice Set the caller's donation share bps; effective next epoch and must be one of {5000, 7500, 10000}
  /// @param bps Donation share in basis points
  function setDonationShareBps(uint16 bps) external; // {5000, 7500, 10000}
  /// @notice Claim user yield for an epoch using a Merkle proof.
  /// @param epoch The epoch index
  /// @param amount The amount encoded in the Merkle leaf for the caller
  /// @param proof The Merkle proof of inclusion
  function claimUserYield(uint256 epoch, uint256 amount, bytes32[] calldata proof) external;

  // Views for router/integrations
  function donationAsset() external view returns (address);
  /// @notice Returns the donation total recorded for a given epoch
  /// @param epoch The epoch index
  function donationAmountForEpoch(uint256 epoch) external view returns (uint256);
  /// @notice Returns the finalized Merkle root for an epoch
  /// @param epoch The epoch index
  function epochRoot(uint256 epoch) external view returns (bytes32);
}
