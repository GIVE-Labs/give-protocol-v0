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

contract Test08_Harvest_EdgeCases is Test {
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);
  address mgr = address(0xCAFE);
  MockERC20Decimals usdc;
  SimpleVault4626Upgradeable vault;
  SimpleHoldingAdapter adapter;
  NGORegistrySimple reg;
  DonationPayer payer;
  TreasurySimple tre;

  function setUp() public {
    usdc = new MockERC20Decimals("USDC", "USDC", 6);
    SimpleVault4626Upgradeable impl = new SimpleVault4626Upgradeable();
    adapter = new SimpleHoldingAdapter(address(usdc), address(0));
    tre = new TreasurySimple(owner);
    reg = new NGORegistrySimple(owner, mgr);
    payer = new DonationPayer(owner);
    bytes memory initData = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(usdc)), "GIVE-100", "G100",
      address(adapter), address(tre), address(payer), address(reg), owner, guardian,
      uint16(10_000), uint16(150), 1_000_000 * 1e6, 2
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    vault = SimpleVault4626Upgradeable(payable(address(new TransparentUpgradeableProxy(address(impl), address(admin), initData))));
    adapter.setVault(address(vault));
    vm.prank(owner);
    payer.setAuthorizedCaller(address(vault), true);
    // NGO setup
    vm.prank(mgr); reg.announceAdd(address(0xABC));
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(mgr); reg.add(address(0xABC));
    vm.prank(owner); vault.queueCurrentNGO(address(0xABC));
    vm.warp(block.timestamp + 48 hours);
    vm.prank(owner); vault.switchCurrentNGO();
  }

  function test_ZeroHarvest_OpensWindow_NoTransfers() public {
    // no deposits or yield
    // calling harvest with current NGO should not revert, opens window
    vault.harvest(address(0xABC));
    // attempt deposit should revert due to window
    vm.expectRevert(SimpleVault4626Upgradeable.DepositsPausedErr.selector);
    vault.deposit(0, address(this));
  }

  function test_SmallAmounts_Rounding() public {
    // deposit tiny amount
    usdc.mint(address(this), 10_000); // 0.01 USDC
    usdc.approve(address(vault), type(uint256).max);
    vault.deposit(10_000, address(this));
    // add tiny yield
    usdc.mint(address(adapter), 3); // 0.000003 USDC
    // fee 1.5% of 3 rounds down to 0; donation 100% => donated==3
    uint256 ngoBefore = usdc.balanceOf(address(0xABC));
    vault.harvest(address(0xABC));
    uint256 ngoAfter = usdc.balanceOf(address(0xABC));
    assertEq(ngoAfter - ngoBefore, 3);
  }
}
