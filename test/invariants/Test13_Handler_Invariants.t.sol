// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20Decimals} from "src/mocks/MockERC20Decimals.sol";
import {SimpleVault4626Upgradeable} from "src/vault/SimpleVault4626Upgradeable.sol";
import {SimpleHoldingAdapter} from "src/adapter/SimpleHoldingAdapter.sol";
import {DonationPayer} from "src/ngo/DonationPayer.sol";
import {NGORegistrySimple} from "src/ngo/NGORegistrySimple.sol";
import {TreasurySimple} from "src/governance/TreasurySimple.sol";
import {MockERC20Decimals} from "src/mocks/MockERC20Decimals.sol";

contract Handler {
  IERC20 public immutable token;
  SimpleVault4626Upgradeable public immutable vault;
  SimpleHoldingAdapter public immutable adapter;
  address public immutable actor; // handler acts as the user
  address public immutable ngo;

  constructor(IERC20 _token, SimpleVault4626Upgradeable _vault, SimpleHoldingAdapter _adapter, address _ngo) {
    token = _token; vault = _vault; adapter = _adapter; ngo = _ngo; actor = address(this);
  }

  function deposit(uint256 amt) external {
    uint256 md = vault.maxDeposit(actor);
    if (md == 0) return;
    uint256 bal = token.balanceOf(actor);
    uint256 want = amt;
    if (want == 0) want = 1;
    if (bal < want) {
      // top up just enough to deposit
      MockERC20Decimals(address(token)).mint(actor, want - bal);
    }
    uint256 upper = md < want ? md : want;
    token.approve(address(vault), type(uint256).max);
    vault.deposit(upper, actor);
  }

  function withdraw(uint256 amt) external {
    uint256 maxAssets = vault.maxWithdraw(actor);
    if (maxAssets == 0) return;
    uint256 size = amt == 0 ? 1 : amt;
    uint256 toWithdraw = size > maxAssets ? maxAssets : size;
    vault.withdraw(toWithdraw, actor, actor);
  }

  function harvest() external {
    // simulate small yield at adapter (mock token)
    MockERC20Decimals(address(token)).mint(address(adapter), 1e6);
    vault.harvest(ngo);
  }
}

contract Test13_Handler_Invariants is StdInvariant, Test {
  MockERC20Decimals token;
  SimpleVault4626Upgradeable vault;
  SimpleHoldingAdapter adapter;
  DonationPayer payer;
  NGORegistrySimple reg;
  TreasurySimple tre;
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);
  address mgr = address(0xCAFE);
  address user = address(0xD00D);
  address ngo = address(0x123456);

  Handler handler;

  function setUp() public {
    token = new MockERC20Decimals("USDC", "USDC", 6);
    SimpleVault4626Upgradeable impl = new SimpleVault4626Upgradeable();
    adapter = new SimpleHoldingAdapter(address(token), address(0));
    tre = new TreasurySimple(owner);
    reg = new NGORegistrySimple(owner, mgr);
    payer = new DonationPayer(owner);
    bytes memory init = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(token)), "GIVE-75", "G75",
      address(adapter), address(tre), address(payer), address(reg), owner, guardian,
      uint16(7500), uint16(100), 1_000_000 * 1e6, 5
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    vault = SimpleVault4626Upgradeable(payable(address(new TransparentUpgradeableProxy(address(impl), address(admin), init))));
    adapter.setVault(address(vault));
    vm.prank(owner); payer.setAuthorizedCaller(address(vault), true);
    // NGO setup
    vm.prank(mgr); reg.announceAdd(ngo);
    vm.warp(block.timestamp + reg.ADD_DELAY());
    vm.prank(mgr); reg.add(ngo);
    vm.prank(owner); vault.queueCurrentNGO(ngo);
    vm.warp(block.timestamp + 48 hours);
    vm.prank(owner); vault.switchCurrentNGO();
    // seed user
    token.mint(user, 500_000 * 1e6);

    handler = new Handler(IERC20(address(token)), vault, adapter, ngo);
    targetContract(address(handler));
    // target selector configuration
    bytes4[] memory sels = new bytes4[](3);
    sels[0] = Handler.deposit.selector;
    sels[1] = Handler.withdraw.selector;
    sels[2] = Handler.harvest.selector;
    targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
  }

  function invariant_withdraw_never_paused() public {
    // Always can withdraw a tiny amount if user has shares
    uint256 maxAssets = vault.maxWithdraw(user);
    if (maxAssets > 0) {
      vm.startPrank(user);
      vault.withdraw(1, user, user);
      vm.stopPrank();
    }
  }

  function invariant_approvals_zero() public {
    assertEq(IERC20(address(token)).allowance(address(vault), address(adapter)), 0);
  }
}
