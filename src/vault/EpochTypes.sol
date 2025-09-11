// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title EpochTypes
/// @notice Types shared across vault epoch accounting and Merkle finalization.
library EpochTypes {
  /// @notice Totals for an epoch used to enforce the conservation identity
  /// @dev harvested == fee + donationTotal + userYieldTotal must hold for every epoch
  struct EpochTotals {
    uint256 harvested;
    uint256 fee;
    uint256 donationTotal;
    uint256 userYieldTotal;
  }
}
