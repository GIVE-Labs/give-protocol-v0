// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StrategyManager} from "src/vault/StrategyManager.sol";

/// @title Test02_StrategyManager
/// @notice Unit tests for StrategyManager (single active adapter, rotation timelock, caps)
contract Test02_StrategyManager is Test {
  StrategyManager sm;
  address admin = address(0xA11CE);
  address stratMgr = address(0xBEEF);

  function setUp() public {
    sm = new StrategyManager(admin, stratMgr);
  }

  /// @notice Scheduling, enforcing delay, and setting active adapter works
  function test_ScheduleAndRotateAdapter() public {
    address adapter = address(0xADAD);
    vm.prank(stratMgr);
    sm.scheduleActiveAdapter(adapter);
    // cannot set before delay
    vm.prank(stratMgr);
    vm.expectRevert(StrategyManager.RotationNotReady.selector);
    sm.setActiveAdapter(adapter);
    // after delay
    vm.warp(block.timestamp + sm.ROTATION_DELAY());
    vm.prank(stratMgr);
    sm.setActiveAdapter(adapter);
    assertEq(sm.activeAdapter(), adapter);
  }

  /// @notice Cancelling a queued rotation disallows activation after delay
  function test_CancelRotation() public {
    address adapter = address(0xADAD);
    vm.prank(stratMgr);
    sm.scheduleActiveAdapter(adapter);
    vm.prank(stratMgr);
    sm.cancelActiveAdapterRotation();
    vm.warp(block.timestamp + sm.ROTATION_DELAY());
    vm.prank(stratMgr);
    vm.expectRevert(StrategyManager.RotationNotReady.selector);
    sm.setActiveAdapter(adapter);
  }

  /// @notice Setting TVL and exposure caps updates state
  function test_SetCaps() public {
    vm.prank(stratMgr);
    sm.setCaps(1_000_000 ether, 5000);
    assertEq(sm.tvlCap(), 1_000_000 ether);
    assertEq(sm.maxExposureBps(), 5000);
  }
}
