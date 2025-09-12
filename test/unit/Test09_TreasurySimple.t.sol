// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasurySimple} from "src/governance/TreasurySimple.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

contract Test09_TreasurySimple is Test {
  TreasurySimple tre;
  MockERC20 token;
  address owner = address(0xA11CE);
  address sender = address(0xB0B);
  address ops = address(0xD00D);

  function setUp() public {
    tre = new TreasurySimple(owner);
    token = new MockERC20("AST", "AST");
  }

  function test_ReceiveFee_And_Sweep() public {
    token.mint(sender, 100 ether);
    vm.startPrank(sender);
    token.approve(address(tre), 100 ether);
    tre.receiveFee(address(token), 60 ether);
    vm.stopPrank();
    assertEq(token.balanceOf(address(tre)), 60 ether);
    vm.prank(owner);
    tre.sweep(address(token), ops, 10 ether);
    assertEq(token.balanceOf(ops), 10 ether);
  }
}
