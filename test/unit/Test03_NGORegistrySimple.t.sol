// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NGORegistrySimple} from "src/ngo/NGORegistrySimple.sol";

contract Test03_NGORegistrySimple is Test {
  NGORegistrySimple reg;
  address admin = address(0xA11CE);
  address mgr = address(0xBEEF);
  address ngo = address(0x1234);

  function setUp() public {
    reg = new NGORegistrySimple(admin, mgr);
  }

  function test_AnnounceAndAdd_Delay() public {
    vm.prank(mgr);
    reg.announceAdd(ngo);
    vm.expectRevert(NGORegistrySimple.TooSoon.selector);
    vm.prank(mgr);
    reg.add(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(mgr);
    reg.add(ngo);
    assertTrue(reg.isAllowed(ngo));
  }

  function test_Add_NotQueuedReverts() public {
    vm.expectRevert(NGORegistrySimple.NotQueued.selector);
    vm.prank(mgr);
    reg.add(ngo);
  }

  function test_Revoke_Immediate() public {
    vm.startPrank(mgr);
    reg.announceAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    reg.add(ngo);
    assertTrue(reg.isAllowed(ngo));
    reg.revoke(ngo);
    assertFalse(reg.isAllowed(ngo));
    vm.stopPrank();
  }
}

