// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {GiveVault4626} from "src/vault/GiveVault4626.sol";
import {StrategyManager} from "src/vault/StrategyManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyManager} from "src/interfaces/IStrategyManager.sol";
import {EpochTypes} from "src/vault/EpochTypes.sol";

/// @title Test01_VaultCore
/// @notice Unit tests for GiveVault4626 core flows (ERC-4626 math, harvest window, fees, epoch lifecycle, Merkle claims, donation share)
/// @dev Naming format follows `TestNN_Description` for professional consistency.
contract Test01_VaultCore is Test {
  event DonationShareSet(address indexed user, uint16 bps, uint256 effectiveEpoch);
  MockERC20 asset;
  StrategyManager sm;
  GiveVault4626 vault;
  address admin = address(0xA11CE);
  address stratMgr = address(0xBEEF);
  address treasury = address(0xFEE);
  address adapter = address(0xADAD);
  address user = address(0xC0FFEE);

  function setUp() public {
    asset = new MockERC20("Mock", "M");
    sm = new StrategyManager(admin, stratMgr);
    vault = new GiveVault4626(ERC20(address(asset)), "GiveVault", "GV", address(sm), treasury, 100, 10);
    // fund vault and users
    asset.mint(user, 1_000_000 ether);
    // do not pre-seed vault here; seed in specific tests to avoid zero-share mints
    // grant role to schedule rotation
    vm.prank(stratMgr);
    sm.scheduleActiveAdapter(adapter);
    vm.warp(block.timestamp + sm.ROTATION_DELAY());
    vm.prank(stratMgr);
    sm.setActiveAdapter(adapter);
  }

  /// @notice Depositing and withdrawing basic amounts works and returns shares
  function test_DepositWithdraw_Basic() public {
    vm.startPrank(user);
    asset.approve(address(vault), type(uint256).max);
    uint256 shares = vault.deposit(100 ether, user);
    assertGt(shares, 0);
    vault.withdraw(10 ether, user, user);
    vm.stopPrank();
  }

  /// @notice Harvest window should block deposit/mint but not withdraw/redeem
  function test_HarvestWindowBlocksDepositNotWithdraw() public {
    asset.mint(address(vault), 100 ether);
    // Report harvest to open window
    vm.prank(adapter);
    vault.reportHarvest(100 ether);
    // deposit should revert
    vm.startPrank(user);
    asset.approve(address(vault), type(uint256).max);
    vm.expectRevert(bytes4(keccak256("HarvestWindowOpen()")));
    vault.deposit(1 ether, user);
    // withdraw should succeed
    vault.redeem(0, user, user); // redeem 0 is no-op
    vm.stopPrank();
  }

  /// @notice Only the active adapter can report; protocol fee is transferred to treasury
  function test_ReportHarvestOnlyActiveAdapterAndFee() public {
    asset.mint(address(vault), 100 ether);
    uint256 tBefore = asset.balanceOf(treasury);
    // wrong caller
    vm.expectRevert(bytes4(keccak256("OnlyActiveAdapter()")));
    vault.reportHarvest(50 ether);
    // right caller
    vm.prank(adapter);
    vault.reportHarvest(100 ether); // fee 1% => 1 ether
    uint256 tAfter = asset.balanceOf(treasury);
    assertEq(tAfter - tBefore, 1 ether);
  }

  /// @notice End-to-end for epoch: report → roll → finalize root → user claims (single-leaf root)
  function test_RollEpochAndFinalizeRootAndClaim() public {
    asset.mint(address(vault), 200 ether);
    // harvest 100
    vm.prank(adapter);
    vault.reportHarvest(100 ether);
    // close and open new epoch
    vault.rollEpoch();
    // finalize root for epoch 0 with user yield 90 and fee 1
    EpochTypes.EpochTotals memory totals = EpochTypes.EpochTotals({
      harvested: 100 ether,
      fee: 1 ether,
      donationTotal: 9 ether,
      userYieldTotal: 90 ether
    });
    // single-leaf root
    bytes32 leaf = keccak256(abi.encodePacked(user, uint256(10 ether)));
    bytes32 root = leaf;
    vault.finalizeEpochRoot(0, root, totals);
    // claim
    vm.prank(user);
    vault.claimUserYield(0, 10 ether, new bytes32[](0));
    assertEq(asset.balanceOf(user), 1_000_010 ether);
    // second claim should revert
    vm.prank(user);
    vm.expectRevert(bytes4(keccak256("AlreadyClaimed()")));
    vault.claimUserYield(0, 10 ether, new bytes32[](0));
  }

  /// @notice Donation share must be one of {5000, 7500, 10000} and becomes effective next epoch
  function test_DonationShare_OnlyAllowedAndNextEpoch() public {
    uint256 cur = vault.currentEpoch();
    // invalid bps reverts
    vm.expectRevert(bytes4(keccak256("InvalidDonationShare()")));
    vault.setDonationShareBps(6000);

    // valid bps emits event with next-epoch effective
    vm.expectEmit(true, true, false, true);
    emit DonationShareSet(user, 5000, cur + 1);
    vm.prank(user);
    vault.setDonationShareBps(5000);
  }

  /// @notice Finalization reverts if conservation identity does not hold: harvested != fee + donation + userYield
  function test_FinalizeRoot_ConservationChecked() public {
    // harvest 100 and roll
    asset.mint(address(vault), 200 ether);
    vm.prank(adapter);
    vault.reportHarvest(100 ether);
    vault.rollEpoch();

    // Provide mismatched totals: sums to 91 instead of 100
    EpochTypes.EpochTotals memory bad = EpochTypes.EpochTotals({
      harvested: 100 ether,
      fee: 1 ether,
      donationTotal: 10 ether,
      userYieldTotal: 80 ether
    });
    bytes32 root = keccak256(abi.encodePacked(user, uint256(1)));
    vm.expectRevert(bytes4(keccak256("InvalidParam()")));
    vault.finalizeEpochRoot(0, root, bad);
  }
}
