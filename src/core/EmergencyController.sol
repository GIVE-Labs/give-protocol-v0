// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title EmergencyController
/// @notice Per-selector pause/unpause; must never pause withdraw/redeem
abstract contract EmergencyController {
  // withdraw(uint256,address,address)
  bytes4 internal constant SELECTOR_WITHDRAW = bytes4(keccak256("withdraw(uint256,address,address)"));
  // redeem(uint256,address,address)
  bytes4 internal constant SELECTOR_REDEEM = bytes4(keccak256("redeem(uint256,address,address)"));

  mapping(bytes4 => bool) internal _paused;

  event SelectorPaused(bytes4 indexed selector, bool paused);

  error CannotPauseWithdrawOrRedeem();

  function setPaused(bytes4 selector, bool paused) external virtual;
  function isPaused(bytes4 selector) public view virtual returns (bool);

  uint256[50] private __gap;
}

