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

contract Test10_E2E_MVP is Test {
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);
  address mgr = address(0xCAFE);
  address user = address(0xD00D);

  MockERC20Decimals usdc;
  SimpleVault4626Upgradeable vault;
  SimpleHoldingAdapter adapter;
  NGORegistrySimple reg;
  DonationPayer payer;
  TreasurySimple tre;
  address ngo;

  function setUp() public {
    usdc = new MockERC20Decimals("USDC", "USDC", 6);
    SimpleVault4626Upgradeable impl = new SimpleVault4626Upgradeable();
    adapter = new SimpleHoldingAdapter(address(usdc), address(0));
    tre = new TreasurySimple(owner);
    reg = new NGORegistrySimple(owner, mgr);
    payer = new DonationPayer(owner);
    bytes memory init = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(usdc)), "GIVE-50", "G50",
      address(adapter), address(tre), address(payer), address(reg), owner, guardian,
      uint16(5000), uint16(100), 1_000_000 * 1e6, 10
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    vault = SimpleVault4626Upgradeable(payable(address(new TransparentUpgradeableProxy(address(impl), address(admin), init))));
    adapter.setVault(address(vault));
    vm.prank(owner); payer.setAuthorizedCaller(address(vault), true);

    // NGO lifecycle
    ngo = address(0xABCD);
    vm.prank(mgr); reg.announceAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(mgr); reg.add(ngo);
    vm.prank(owner); vault.queueCurrentNGO(ngo);
    vm.warp(block.timestamp + 48 hours);
    vm.prank(owner); vault.switchCurrentNGO();

    // User funding
    usdc.mint(user, 1_000_000 * 1e6);
  }

  function test_E2E_Deposit_Harvest_Donate_Withdraw() public {
    // deposit
    vm.startPrank(user);
    usdc.approve(address(vault), type(uint256).max);
    vault.deposit(100_000 * 1e6, user);
    vm.stopPrank();

    // realize yield at adapter
    usdc.mint(address(adapter), 1_000 * 1e6);
    uint256 ngoBefore = usdc.balanceOf(ngo);
    uint256 treBefore = usdc.balanceOf(address(tre));

    // harvest to current NGO
    vault.harvest(ngo);
    uint256 ngoAfter = usdc.balanceOf(ngo);
    uint256 treAfter = usdc.balanceOf(address(tre));
    // fee 1% of 1000 => 10; donation 50% of 990 => 495
    assertEq(treAfter - treBefore, 10 * 1e6);
    assertEq(ngoAfter - ngoBefore, 495 * 1e6);

    // withdraw all for user (principal safety)
    vm.prank(user);
    vault.withdraw(100_000 * 1e6, user, user);
  }
}
