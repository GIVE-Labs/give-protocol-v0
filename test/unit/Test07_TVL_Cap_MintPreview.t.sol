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

contract Test07_TVL_Cap_MintPreview is Test {
  address owner = address(0xA11CE);
  address guardian = address(0xBEEF);

  MockERC20Decimals usdc;
  SimpleVault4626Upgradeable vault;

  function setUp() public {
    usdc = new MockERC20Decimals("USDC", "USDC", 6);
    SimpleVault4626Upgradeable impl = new SimpleVault4626Upgradeable();
    SimpleHoldingAdapter adapter = new SimpleHoldingAdapter(address(usdc), address(0));
    TreasurySimple tre = new TreasurySimple(owner);
    NGORegistrySimple reg = new NGORegistrySimple(owner, owner);
    DonationPayer payer = new DonationPayer(owner);
    bytes memory initData = abi.encodeWithSelector(
      SimpleVault4626Upgradeable.initialize.selector,
      IERC20(address(usdc)), "GIVE-75", "G75",
      address(adapter), address(tre), address(payer), address(reg), owner, guardian,
      uint16(7500), uint16(100), 100_000 * 1e6, 3
    );
    ProxyAdmin admin = new ProxyAdmin(address(this));
    vault = SimpleVault4626Upgradeable(payable(address(new TransparentUpgradeableProxy(address(impl), address(admin), initData))));
    adapter.setVault(address(vault));
    vm.prank(owner);
    payer.setAuthorizedCaller(address(vault), true);
  }

  function test_MaxDepositReflectsCap() public {
    assertEq(vault.maxDeposit(address(this)), 100_000 * 1e6);
  }

  function test_MintRespectsCap() public {
    usdc.mint(address(this), 200_000 * 1e6);
    usdc.approve(address(vault), type(uint256).max);
    // First, deposit 90k
    vault.deposit(90_000 * 1e6, address(this));
    // Remaining cap 10k; try minting shares previewed to >10k assets should revert
    uint256 shares = vault.previewDeposit(15_000 * 1e6);
    vm.expectRevert();
    vault.mint(shares, address(this));
    // Mint within cap works
    uint256 sharesOk = vault.previewDeposit(10_000 * 1e6);
    vault.mint(sharesOk, address(this));
  }
}
