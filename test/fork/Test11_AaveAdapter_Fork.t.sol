// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleAaveAdapter} from "src/adapter/SimpleAaveAdapter.sol";

/// @notice Fork test scaffold for Aave V3.1 on Base. Skips if env is not set.
contract Test11_AaveAdapter_Fork is Test {
  address ASSET;
  address ATOKEN;
  address POOL;
  address VAULT = address(0xBEEF);

  function setUp() public {
    // if not configured, test will no-op
    ASSET = vm.envOr("ASSET", address(0));
    ATOKEN = vm.envOr("ATOKEN", address(0));
    POOL = vm.envOr("AAVE_POOL", address(0));
  }

  function test_DepositWithdraw_Aave() public {
    if (ASSET == address(0) || ATOKEN == address(0) || POOL == address(0)) return;
    SimpleAaveAdapter adapter = new SimpleAaveAdapter(ASSET, ATOKEN, POOL, VAULT);
    // Impersonate vault and fund with asset
    vm.startPrank(VAULT);
    deal(ASSET, VAULT, 1000e6); // works for USDC-like; adjust decimals via env in practice
    IERC20(ASSET).approve(address(adapter), type(uint256).max);
    adapter.deposit(100e6);
    // Withdraw
    adapter.withdraw(50e6, VAULT);
    vm.stopPrank();
  }
}
