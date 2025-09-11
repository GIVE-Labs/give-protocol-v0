// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NGORegistry} from "src/donation/NGORegistry.sol";

/// @title Test03_NGORegistry
/// @notice Unit tests for NGORegistry (two-step add, eligibility, revocations)
contract Test03_NGORegistry is Test {
  NGORegistry reg;
  address admin = address(0xA11CE);
  address manager = address(0xBEEF);
  address ngo = address(0xD00D);

  function setUp() public {
    reg = new NGORegistry(admin, manager);
  }

  /// @notice Queue and finalize add enforces delay; eligibility reflects timestamps
  function test_AddAndEligibility() public {
    vm.prank(manager);
    reg.queueAdd(ngo);
    vm.expectRevert(NGORegistry.TooSoon.selector);
    vm.prank(manager);
    reg.finalizeAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(manager);
    reg.finalizeAdd(ngo);
    assertTrue(reg.isAllowed(ngo));
    uint256 ts = block.timestamp;
    assertTrue(reg.isEligibleAt(ngo, ts));
  }

  /// @notice Emergency revoke disables eligibility for future timestamps
  function test_RevokeAndEmergencyRevoke() public {
    vm.prank(manager);
    reg.queueAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(manager);
    reg.finalizeAdd(ngo);
    assertTrue(reg.isAllowed(ngo));
    vm.prank(manager);
    reg.emergencyRevoke(ngo);
    assertFalse(reg.isAllowed(ngo));
    // After revocation time, eligibility is false
    assertFalse(reg.isEligibleAt(ngo, block.timestamp + 1));
  }
}
