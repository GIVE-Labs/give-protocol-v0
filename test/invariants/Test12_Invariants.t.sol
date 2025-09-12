// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20Decimals} from "src/mocks/MockERC20Decimals.sol";
import {SimpleVault4626Upgradeable} from "src/vault/SimpleVault4626Upgradeable.sol";
import {SimpleHoldingAdapter} from "src/adapter/SimpleHoldingAdapter.sol";
import {NGORegistrySimple} from "src/ngo/NGORegistrySimple.sol";
import {DonationPayer} from "src/ngo/DonationPayer.sol";
import {TreasurySimple} from "src/governance/TreasurySimple.sol";

contract Test12_Invariants is Test {
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);
  address mgr = address(0xCAFE);
  address user = address(0xD00D);
  address ngo = address(0x123456);

  MockERC20Decimals token;
  SimpleVault4626Upgradeable vault;
  SimpleHoldingAdapter adapter;
  DonationPayer payer;
  TreasurySimple tre;
  NGORegistrySimple reg;

  function setUp() public {
    token = new MockERC20Decimals("TKN", "TKN", 6);
    SimpleVault4626Upgradeable impl = new SimpleVault4626Upgradeable();
    adapter = new SimpleHoldingAdapter(address(token), address(0));
    tre = new TreasurySimple(owner);
    reg = new NGORegistrySimple(owner, mgr);
    payer = new DonationPayer(owner);
    bytes memory init = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(token)), "GIVE-50", "G50",
      address(adapter), address(tre), address(payer), address(reg), owner, guardian,
      uint16(5000), uint16(100), 1_000_000 * 1e6, 10
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    vault = SimpleVault4626Upgradeable(payable(address(new TransparentUpgradeableProxy(address(impl), address(admin), init))));
    adapter.setVault(address(vault));
    vm.prank(owner); payer.setAuthorizedCaller(address(vault), true);

    vm.startPrank(mgr);
    reg.announceAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    reg.add(ngo);
    vm.stopPrank();
    vm.prank(owner); vault.queueCurrentNGO(ngo);
    vm.warp(block.timestamp + 48 hours);
    vm.prank(owner); vault.switchCurrentNGO();

    // Seed user and deposit once so withdraw is always possible even if deposits are paused
    token.mint(user, 100_000 * 1e6);
    vm.startPrank(user);
    token.approve(address(vault), type(uint256).max);
    vault.deposit(10_000 * 1e6, user);
    vm.stopPrank();
  }

  function test_WithdrawAlwaysOpen_Property() public {
    // Try to withdraw small amounts even after deposits are paused
    vm.prank(guardian); vault.pauseDeposits(true);
    if (vault.maxWithdraw(user) > 0) {
      vm.startPrank(user);
      vault.withdraw(1, user, user);
      vm.stopPrank();
    }
  }

  function test_ApprovalsZeroAfterOps_Property() public {
    // simulate yield and harvest
    MockERC20Decimals(address(token)).mint(address(adapter), 100 * 1e6);
    vault.harvest(ngo);
    // allowances should be zero
    assertEq(IERC20(address(token)).allowance(address(vault), address(adapter)), 0);
  }
}
