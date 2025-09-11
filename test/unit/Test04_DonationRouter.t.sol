// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DonationRouter} from "src/donation/DonationRouter.sol";
import {NGORegistry} from "src/donation/NGORegistry.sol";
import {GiveVault4626} from "src/vault/GiveVault4626.sol";
import {StrategyManager} from "src/vault/StrategyManager.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EpochTypes} from "src/vault/EpochTypes.sol";

/// @title Test04_DonationRouter
/// @notice Unit tests for DonationRouter (settlement, pro-rata claims, emergency revoke behavior)
contract Test04_DonationRouter is Test {
  MockERC20 asset;
  StrategyManager sm;
  GiveVault4626 vault;
  NGORegistry reg;
  DonationRouter router;

  address admin = address(0xA11CE);
  address stratMgr = address(0xBEEF);
  address treasury = address(0xFEE);
  address adapter = address(0xADAD);
  address ngo1 = address(0xAAA1);
  address ngo2 = address(0xAAA2);

  function setUp() public {
    asset = new MockERC20("Mock", "M");
    sm = new StrategyManager(admin, stratMgr);
    vault = new GiveVault4626(ERC20(address(asset)), "GiveVault", "GV", address(sm), treasury, 100, 10);
    reg = new NGORegistry(admin, admin);
    router = new DonationRouter(address(vault), address(reg), admin);
    // Seed vault with assets to transfer to NGOs on claim
    asset.mint(address(vault), 1_000_000 ether);
    // Activate adapter
    vm.prank(stratMgr);
    sm.scheduleActiveAdapter(adapter);
    vm.warp(block.timestamp + sm.ROTATION_DELAY());
    vm.prank(stratMgr);
    sm.setActiveAdapter(adapter);
  }

  /// @dev Utility to report, roll as needed, and finalize a Merkle root with given totals
  function _harvestAndFinalize(uint256 epoch, uint256 amount, uint256 donation, uint256 userYield) internal {
    vm.prank(adapter);
    vault.reportHarvest(amount);
    while (vault.currentEpoch() <= epoch) {
      vault.rollEpoch();
    }
    EpochTypes.EpochTotals memory totals = EpochTypes.EpochTotals({
      harvested: amount,
      fee: (amount * 100) / 10_000,
      donationTotal: donation,
      userYieldTotal: userYield
    });
    bytes32 root = bytes32(uint256(keccak256(abi.encodePacked(address(0x1), uint256(1)) )));
    vault.finalizeEpochRoot(epoch, root, totals);
  }

  /// @notice Settlement snapshots donation and NGO count; claims split pro-rata across NGOs
  function test_SettleAndClaimProRata() public {
    // add ngos
    vm.prank(admin);
    reg.queueAdd(ngo1);
    vm.prank(admin);
    reg.queueAdd(ngo2);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(admin);
    reg.finalizeAdd(ngo1);
    vm.prank(admin);
    reg.finalizeAdd(ngo2);

    // epoch 0: donation 100
    // conservation with 1% fee: 1 + 99 + 0 = 100
    _harvestAndFinalize(0, 100 ether, 99 ether, 0);
    router.settleEpoch(0);

    // approve router by vault to transfer donation asset
    vm.prank(address(vault));
    asset.approve(address(router), type(uint256).max);

    // both claim, each gets 50
    vm.prank(ngo1);
    uint256 c1 = router.claim(ngo1, ngo1);
    vm.prank(ngo2);
    uint256 c2 = router.claim(ngo2, ngo2);
    assertEq(c1, 49.5 ether);
    assertEq(c2, 49.5 ether);
  }

  /// @notice Emergency revoke should not affect already settled epochs; blocks future accruals
  function test_EmergencyRevokeBlocksFutureEpochs() public {
    vm.prank(admin);
    reg.queueAdd(ngo1);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(admin);
    reg.finalizeAdd(ngo1);

    // epoch 0 settle with 99 donation
    _harvestAndFinalize(0, 100 ether, 99 ether, 0);
    router.settleEpoch(0);
    assertTrue(router.epochSettled(0));
    assertEq(router.epochNgoCount(0), 1);
    assertEq(router.epochDonation(0), 99 ether);

    // revoke
    vm.prank(admin);
    reg.emergencyRevoke(ngo1);
    vm.prank(address(vault));
    asset.approve(address(router), type(uint256).max);

    // claim now: only epoch 0 is settled
    (uint256 p0,,) = router.pendingAmount(ngo1);
    assertEq(p0, 99 ether);
    vm.prank(ngo1);
    uint256 amount = router.claim(ngo1, ngo1);
    assertEq(amount, 99 ether);

    // epoch 1 with new amounts to keep fee integral: use 100
    _harvestAndFinalize(1, 100 ether, 99 ether, 0);
    router.settleEpoch(1);
    (uint256 pending,,) = router.pendingAmount(ngo1);
    assertEq(pending, 0);
  }
}
