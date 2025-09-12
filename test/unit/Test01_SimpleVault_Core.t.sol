// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockERC20Decimals} from "src/mocks/MockERC20Decimals.sol";
import {SimpleVault4626Upgradeable} from "src/vault/SimpleVault4626Upgradeable.sol";
import {SimpleHoldingAdapter} from "src/adapter/SimpleHoldingAdapter.sol";
import {NGORegistrySimple} from "src/ngo/NGORegistrySimple.sol";
import {DonationPayer} from "src/ngo/DonationPayer.sol";
import {TreasurySimple} from "src/governance/TreasurySimple.sol";

contract Test01_SimpleVault_Core is Test {
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);
  address ngoMgr = address(0xCAFE);
  address user = address(0xD00D);

  MockERC20Decimals usdc; // 6 dec
  SimpleVault4626Upgradeable vaultImpl;
  SimpleVault4626Upgradeable vault;
  SimpleHoldingAdapter adapter;
  NGORegistrySimple reg;
  DonationPayer payer;
  TreasurySimple treasury;

  function setUp() public {
    vm.startPrank(owner);
    usdc = new MockERC20Decimals("USDC", "USDC", 6);
    vaultImpl = new SimpleVault4626Upgradeable();
    treasury = new TreasurySimple(owner);
    reg = new NGORegistrySimple(owner, ngoMgr);
    payer = new DonationPayer(owner);

    // Deploy adapter now; vault proxy later
    adapter = new SimpleHoldingAdapter(address(usdc), address(0));

    bytes memory initData = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(usdc)),
      string("GIVE-50"),
      string("G50"),
      address(adapter),
      address(treasury),
      address(payer),
      address(reg),
      owner,
      guardian,
      uint16(5000), // 50%
      uint16(100),  // 1%
      uint256(1_000_000 * 1e6),
      uint256(20)
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(vaultImpl), address(admin), initData);
    vault = SimpleVault4626Upgradeable(payable(address(proxy)));
    adapter.setVault(address(vault));

    // Authorize vault on payer
    payer.setAuthorizedCaller(address(vault), true);

    // Fund user and approve
    usdc.mint(user, 1_000_000 * 1e6);
    vm.stopPrank();
  }

  function _userDeposit(uint256 assets) internal {
    vm.startPrank(user);
    IERC20(address(usdc)).approve(address(vault), type(uint256).max);
    vault.deposit(assets, user);
    vm.stopPrank();
  }

  function test_DepositWithdraw_Basic() public {
    _userDeposit(100_000 * 1e6);
    vm.prank(user);
    vault.withdraw(10_000 * 1e6, user, user);
  }

  function test_TVLCap_EnforcedOnDeposit() public {
    // set a low cap
    vm.prank(owner);
    vault.setTVLCap(50_000 * 1e6);
    // OK
    _userDeposit(50_000 * 1e6);
    // Exceed reverts
    vm.startPrank(user);
    IERC20(address(usdc)).approve(address(vault), type(uint256).max);
    vm.expectRevert();
    vault.deposit(1, user);
    vm.stopPrank();
  }

  function test_HarvestIdentity_FeeThenDonation() public {
    // set an NGO and wait 48h
    address ngo = address(0x1110001);
    vm.prank(ngoMgr);
    reg.announceAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(ngoMgr);
    reg.add(ngo);

    vm.prank(owner);
    vault.queueCurrentNGO(ngo);
    vm.warp(block.timestamp + 48 hours);
    vm.prank(owner);
    vault.switchCurrentNGO();

    // deposit
    _userDeposit(100_000 * 1e6);

    // simulate yield by minting to adapter (held assets)
    usdc.mint(address(adapter), 1_000 * 1e6); // harvested should see +1,000e6

    uint256 ngoBalBefore = IERC20(address(usdc)).balanceOf(ngo);
    uint256 treBefore = IERC20(address(usdc)).balanceOf(address(treasury));

    // harvest
    vm.expectEmit(true, false, false, true);
    emit SimpleVault4626Upgradeable.Harvest(1_000 * 1e6, 10 * 1e6, 495 * 1e6, 495 * 1e6, ngo);
    vault.harvest(ngo);

    uint256 ngoBalAfter = IERC20(address(usdc)).balanceOf(ngo);
    uint256 treAfter = IERC20(address(usdc)).balanceOf(address(treasury));

    // fee 1% of 1000 = 10; remainder 990; donation 50% => 495; retained 495
    assertEq(treAfter - treBefore, 10 * 1e6);
    assertEq(ngoBalAfter - ngoBalBefore, 495 * 1e6);
  }

  function test_DepositPause_And_WithdrawAlwaysOpen() public {
    _userDeposit(10_000 * 1e6);
    // pause deposits
    vm.prank(guardian);
    vault.pauseDeposits(true);
    // deposit should revert
    vm.startPrank(user);
    IERC20(address(usdc)).approve(address(vault), type(uint256).max);
    vm.expectRevert(SimpleVault4626Upgradeable.DepositsPausedErr.selector);
    vault.deposit(1, user);
    // withdraw must still work
    vault.withdraw(1, user, user);
    vm.stopPrank();
  }

  function test_HarvestWindowBlocksDepositNotWithdraw() public {
    // set NGO
    address ngo = address(0x2220002);
    vm.prank(ngoMgr); reg.announceAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(ngoMgr); reg.add(ngo);
    vm.prank(owner); vault.queueCurrentNGO(ngo);
    vm.warp(block.timestamp + 48 hours);
    vm.prank(owner); vault.switchCurrentNGO();

    _userDeposit(1_000 * 1e6);
    // yield
    usdc.mint(address(adapter), 100 * 1e6);
    // harvest opens window
    vault.harvest(ngo);

    // deposit should revert under window
    vm.startPrank(user);
    IERC20(address(usdc)).approve(address(vault), type(uint256).max);
    vm.expectRevert(SimpleVault4626Upgradeable.DepositsPausedErr.selector);
    vault.deposit(1, user);
    // withdraw should succeed
    vault.withdraw(1, user, user);
    vm.stopPrank();
  }
}
