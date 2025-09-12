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

contract Test02_Approvals_Unwind_NGO is Test {
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);
  address ngoMgr = address(0xCAFE);
  address user = address(0xD00D);

  MockERC20 weth; // 18
  SimpleVault4626Upgradeable vaultImpl;
  SimpleVault4626Upgradeable vault;
  SimpleHoldingAdapter adapter;
  NGORegistrySimple reg;
  DonationPayer payer;
  TreasurySimple treasury;

  function setUp() public {
    vm.startPrank(owner);
    weth = new MockERC20("WETH", "WETH");
    vaultImpl = new SimpleVault4626Upgradeable();
    treasury = new TreasurySimple(owner);
    reg = new NGORegistrySimple(owner, ngoMgr);
    payer = new DonationPayer(owner);
    adapter = new SimpleHoldingAdapter(address(weth), address(0));
    bytes memory initData = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(weth)),
      string("GIVE-75"),
      string("G75"),
      address(adapter),
      address(treasury),
      address(payer),
      address(reg),
      owner,
      guardian,
      uint16(7500), // 75%
      uint16(150),  // 1.5%
      uint256(1_000_000 ether),
      uint256(10)
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(vaultImpl), address(admin), initData);
    vault = SimpleVault4626Upgradeable(payable(address(proxy)));
    adapter.setVault(address(vault));
    payer.setAuthorizedCaller(address(vault), true);
    weth.mint(user, 1000 ether);
    vm.stopPrank();
  }

  function _setNGO(address ngo) internal {
    vm.startPrank(ngoMgr);
    reg.announceAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    reg.add(ngo);
    vm.stopPrank();
    vm.prank(owner);
    vault.queueCurrentNGO(ngo);
    vm.warp(block.timestamp + 48 hours);
    vm.prank(owner);
    vault.switchCurrentNGO();
  }

  function test_ApprovalsZeroed_AfterDepositAndHarvest() public {
    address ngo = address(0x1111aa);
    _setNGO(ngo);

    // deposit
    vm.startPrank(user);
    IERC20(address(weth)).approve(address(vault), type(uint256).max);
    vault.deposit(10 ether, user);
    vm.stopPrank();

    // After deposit, allowance from vault to adapter should be zero
    assertEq(IERC20(address(weth)).allowance(address(vault), address(adapter)), 0);

    // simulate yield and harvest
    weth.mint(address(adapter), 1 ether);
    vault.harvest(ngo);

    // After harvest, allowance to DonationPayer should be zero
    assertEq(IERC20(address(weth)).allowance(address(vault), address(payer)), 0);
  }

  function test_EmergencyUnwind_DrainsAdapter_WithdrawsStillWork() public {
    // deposit
    vm.startPrank(user);
    IERC20(address(weth)).approve(address(vault), type(uint256).max);
    vault.deposit(50 ether, user);
    vm.stopPrank();

    // adapter should hold all assets
    uint256 beforeAdapter = IERC20(address(weth)).balanceOf(address(adapter));
    assertEq(beforeAdapter, 50 ether);

    // emergencyUnwind (holding adapter just reports, then vault pulls all)
    vm.prank(guardian);
    vault.emergencyUnwind(10_000);

    uint256 afterAdapter = IERC20(address(weth)).balanceOf(address(adapter));
    // adapter drained
    assertEq(afterAdapter, 0);

    // withdrawals open
    vm.prank(user);
    vault.withdraw(10 ether, user, user);
  }

  function test_NGOEnforced_WrongNGOReverts() public {
    address ngo = address(0x2222bb);
    _setNGO(ngo);

    // deposit and simulate yield
    vm.startPrank(user);
    IERC20(address(weth)).approve(address(vault), type(uint256).max);
    vault.deposit(10 ether, user);
    vm.stopPrank();
    weth.mint(address(adapter), 1 ether);

    // wrong NGO must revert
    vm.expectRevert(SimpleVault4626Upgradeable.NGOForbidden.selector);
    vault.harvest(address(0x3333cc));
  }
}
