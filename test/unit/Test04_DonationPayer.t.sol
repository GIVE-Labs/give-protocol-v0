// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DonationPayer} from "src/ngo/DonationPayer.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

contract Test04_DonationPayer is Test {
  DonationPayer payer;
  MockERC20 asset;

  address owner = address(0xA11CE);
  address vault = address(0x1111);
  address ngo = address(0x2222);

  function setUp() public {
    payer = new DonationPayer(owner);
    asset = new MockERC20("Asset", "AST");
  }

  function test_AuthorizationAndDonate() public {
    // authorize vault
    vm.prank(owner);
    payer.setAuthorizedCaller(vault, true);
    // fund vault and approve payer
    asset.mint(vault, 100 ether);
    vm.prank(vault);
    asset.approve(address(payer), 50 ether);
    // donate
    vm.prank(vault);
    payer.donate(address(asset), ngo, 50 ether);
    assertEq(asset.balanceOf(ngo), 50 ether);
  }

  function test_UnauthorizedReverts() public {
    asset.mint(vault, 1 ether);
    vm.prank(vault);
    asset.approve(address(payer), 1 ether);
    vm.expectRevert(DonationPayer.NotAuthorized.selector);
    vm.prank(vault);
    payer.donate(address(asset), ngo, 1 ether);
  }

  function test_InvalidParamsRevert() public {
    vm.prank(owner);
    payer.setAuthorizedCaller(vault, true);
    vm.expectRevert(DonationPayer.InvalidParam.selector);
    vm.prank(vault);
    payer.donate(address(0), ngo, 1);
    vm.expectRevert(DonationPayer.InvalidParam.selector);
    vm.prank(vault);
    payer.donate(address(asset), address(0), 1);
    vm.expectRevert(DonationPayer.InvalidParam.selector);
    vm.prank(vault);
    payer.donate(address(asset), ngo, 0);
  }
}
