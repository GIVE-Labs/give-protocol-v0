// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {GiveVault4626} from "src/vault/GiveVault4626.sol";
import {StrategyManager} from "src/vault/StrategyManager.sol";
import {DonationRouter} from "src/donation/DonationRouter.sol";
import {NGORegistry} from "src/donation/NGORegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EpochTypes} from "src/vault/EpochTypes.sol";

/// @title Test10_E2E
/// @notice Integration tests for the end-to-end Give Protocol flow across epochs (vault, strategy manager, router, registry)
contract Test10_E2E is Test {
  MockERC20 asset;
  StrategyManager sm;
  GiveVault4626 vault;
  DonationRouter router;
  NGORegistry reg;

  address admin = address(0xA11CE);
  address stratMgr = address(0xBEEF);
  address treasury = address(0xFEE);
  address adapter = address(0xADAD);
  address user = address(0xC0FFEE);
  address ngo = address(0xD00D);
  address user2 = address(0xC0FF11);
  address ngo2 = address(0xD00E);
  address adapter2 = address(0xBADA55);

  function setUp() public {
    asset = new MockERC20("Mock", "M");
    sm = new StrategyManager(admin, stratMgr);
    vault = new GiveVault4626(ERC20(address(asset)), "GiveVault", "GV", address(sm), treasury, 100, 10);
    reg = new NGORegistry(admin, admin);
    router = new DonationRouter(address(vault), address(reg), admin);
  }

  /// @notice Happy-path: deposit → harvest → roll → finalize root → settle → NGO claim → user claim → withdraw
  function test_E2E_Deposit_Harvest_Root_Settle_Claims() public {
    // Seed user balances
    asset.mint(user, 10_000 ether);

    // User deposits before additional yield seeded
    vm.startPrank(user);
    asset.approve(address(vault), type(uint256).max);
    uint256 shares = vault.deposit(1000 ether, user);
    assertGt(shares, 0);
    vm.stopPrank();

    // Seed realized yield into vault for report/claims
    asset.mint(address(vault), 1_000 ether);

    // Activate adapter
    vm.prank(stratMgr);
    sm.scheduleActiveAdapter(adapter);
    vm.warp(block.timestamp + sm.ROTATION_DELAY());
    vm.prank(stratMgr);
    sm.setActiveAdapter(adapter);

    // Report harvest 100 ether
    vm.prank(adapter);
    vault.reportHarvest(100 ether);
    // Close epoch 0 and finalize root
    vault.rollEpoch();
    EpochTypes.EpochTotals memory totals = EpochTypes.EpochTotals({
      harvested: 100 ether,
      fee: 1 ether,
      donationTotal: 30 ether,
      userYieldTotal: 69 ether
    });
    bytes32 userLeaf = keccak256(abi.encodePacked(user, uint256(69 ether)));
    vault.finalizeEpochRoot(0, userLeaf, totals);

    // Add one NGO and settle
    vm.prank(admin);
    reg.queueAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(admin);
    reg.finalizeAdd(ngo);
    router.settleEpoch(0);

    // Approve router from vault to transfer donation asset
    vm.prank(address(vault));
    asset.approve(address(router), type(uint256).max);

    // NGO claims donation total (only 1 NGO => full amount)
    vm.prank(ngo);
    uint256 donated = router.claim(ngo, ngo);
    assertEq(donated, 30 ether);

    // User claims user yield
    uint256 userBefore = asset.balanceOf(user);
    vm.prank(user);
    vault.claimUserYield(0, 69 ether, new bytes32[](0));
    assertEq(asset.balanceOf(user), userBefore + 69 ether);

    // Withdraw some principal still allowed
    vm.prank(user);
    vault.withdraw(10 ether, user, user);
  }

  /// @notice Multi-epoch: two users & NGOs, adapter rotation, emergency revoke before settlement, selective accrual and claims
  function test_E2E_MultiEpoch_TwoUsers_TwoNGOs_RotateAndRevoke() public {
    // Seed balances for users (vault will be funded by user deposits and harvests)
    asset.mint(user, 5_000 ether);
    asset.mint(user2, 5_000 ether);

    // Activate initial adapter
    vm.prank(stratMgr);
    sm.scheduleActiveAdapter(adapter);
    vm.warp(block.timestamp + sm.ROTATION_DELAY());
    vm.prank(stratMgr);
    sm.setActiveAdapter(adapter);

    // Add two NGOs
    vm.startPrank(admin);
    reg.queueAdd(ngo);
    reg.queueAdd(ngo2);
    vm.stopPrank();
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.startPrank(admin);
    reg.finalizeAdd(ngo);
    reg.finalizeAdd(ngo2);
    vm.stopPrank();

    // Users deposit
    vm.startPrank(user);
    asset.approve(address(vault), type(uint256).max);
    vault.deposit(1000 ether, user);
    vm.stopPrank();
    vm.startPrank(user2);
    asset.approve(address(vault), type(uint256).max);
    vault.deposit(500 ether, user2);
    vm.stopPrank();

    // Epoch 0: report and finalize totals
    vm.prank(adapter);
    vault.reportHarvest(200 ether); // 1% fee -> 2
    // Withdraw during harvest window should still work
    vm.prank(user2);
    vault.withdraw(10 ether, user2, user2);
    // Close and finalize root for epoch 0
    vault.rollEpoch();
    EpochTypes.EpochTotals memory t0 = EpochTypes.EpochTotals({
      harvested: 200 ether,
      fee: 2 ether,
      donationTotal: 60 ether,
      userYieldTotal: 138 ether
    });
    // Single-claim leaf for user (part of total userYield)
    bytes32 r0 = keccak256(abi.encodePacked(user, uint256(100 ether)));
    vault.finalizeEpochRoot(0, r0, t0);
    // Settle and split donation across 2 NGOs
    router.settleEpoch(0);

    // Approve router to transfer donation asset from vault
    vm.prank(address(vault));
    asset.approve(address(router), type(uint256).max);

    // NGOs claim epoch 0: each gets 30
    vm.startPrank(ngo);
    uint256 c0a = router.claim(ngo, ngo);
    vm.stopPrank();
    vm.startPrank(ngo2);
    uint256 c0b = router.claim(ngo2, ngo2);
    vm.stopPrank();
    assertEq(c0a, 30 ether);
    assertEq(c0b, 30 ether);

    // Rotate adapter before epoch 1 harvest
    vm.prank(stratMgr);
    sm.scheduleActiveAdapter(adapter2);
    vm.warp(block.timestamp + sm.ROTATION_DELAY());
    vm.prank(stratMgr);
    sm.setActiveAdapter(adapter2);
    // Old adapter cannot report
    vm.expectRevert(bytes4(keccak256("OnlyActiveAdapter()")));
    vault.reportHarvest(1 ether);
    // New adapter reports
    vm.prank(adapter2);
    vault.reportHarvest(100 ether); // 1% fee -> 1
    // Close and finalize root for epoch 1
    vault.rollEpoch();
    EpochTypes.EpochTotals memory t1 = EpochTypes.EpochTotals({
      harvested: 100 ether,
      fee: 1 ether,
      donationTotal: 40 ether,
      userYieldTotal: 59 ether
    });
    bytes32 r1 = keccak256(abi.encodePacked(user2, uint256(59 ether)));
    vault.finalizeEpochRoot(1, r1, t1);

    // Emergency revoke NGO2 BEFORE settle; only NGO1 should accrue epoch 1 donations
    vm.prank(admin);
    reg.emergencyRevoke(ngo2);
    // Advance time to ensure settlement timestamp is strictly after revoke
    vm.warp(block.timestamp + 1);
    router.settleEpoch(1);

    // Pending for NGO1 should be 40 (epoch 1); NGO2 should be 0
    (uint256 p1a,,) = router.pendingAmount(ngo);
    (uint256 p1b,,) = router.pendingAmount(ngo2);
    assertEq(p1a, 40 ether);
    assertEq(p1b, 0);

    // Claims
    vm.prank(ngo);
    uint256 c1a = router.claim(ngo, ngo);
    assertEq(c1a, 40 ether);
    vm.prank(ngo2);
    uint256 c1b = router.claim(ngo2, ngo2);
    assertEq(c1b, 0);

    // Users claim their epoch yields
    vm.prank(user);
    vault.claimUserYield(0, 100 ether, new bytes32[](0));
    vm.prank(user2);
    vault.claimUserYield(1, 59 ether, new bytes32[](0));
  }
}
