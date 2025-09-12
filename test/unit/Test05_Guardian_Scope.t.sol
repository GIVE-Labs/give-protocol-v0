// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {SimpleVault4626Upgradeable} from "src/vault/SimpleVault4626Upgradeable.sol";
import {SimpleHoldingAdapter} from "src/adapter/SimpleHoldingAdapter.sol";
import {NGORegistrySimple} from "src/ngo/NGORegistrySimple.sol";
import {DonationPayer} from "src/ngo/DonationPayer.sol";
import {TreasurySimple} from "src/governance/TreasurySimple.sol";

contract Test05_Guardian_Scope is Test {
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);
  MockERC20 asset;
  SimpleVault4626Upgradeable vault;
  SimpleVault4626Upgradeable impl;

  function setUp() public {
    asset = new MockERC20("AST", "AST");
    impl = new SimpleVault4626Upgradeable();
    SimpleHoldingAdapter adapter = new SimpleHoldingAdapter(address(asset), address(0));
    TreasurySimple tre = new TreasurySimple(owner);
    NGORegistrySimple reg = new NGORegistrySimple(owner, owner);
    DonationPayer payer = new DonationPayer(owner);
    bytes memory initData = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(asset)), "GIVE-100", "G100",
      address(adapter), address(tre), address(payer), address(reg), owner, guardian,
      uint16(10_000), uint16(10), 1_000_000 ether, 5
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    vault = SimpleVault4626Upgradeable(payable(address(new TransparentUpgradeableProxy(address(impl), address(admin), initData))));
    adapter.setVault(address(vault));
    vm.prank(owner);
    payer.setAuthorizedCaller(address(vault), true);
  }

  function test_Guardian_CanPauseDeposits_And_Unwind() public {
    vm.prank(guardian);
    vault.pauseDeposits(true);
    vm.prank(guardian);
    vault.emergencyUnwind(10_000);
  }

  function test_Guardian_CannotSetOwnerParams() public {
    vm.expectRevert(); vm.prank(guardian); vault.setTVLCap(0);
    vm.expectRevert(); vm.prank(guardian); vault.queueCurrentNGO(address(0x1));
    vm.expectRevert(); vm.prank(guardian); vault.switchCurrentNGO();
    vm.expectRevert(); vm.prank(guardian); vault.setGuardian(address(0x2));
    vm.expectRevert(); vm.prank(guardian); vault.setProtocolFeeBps(1);
  }
}
