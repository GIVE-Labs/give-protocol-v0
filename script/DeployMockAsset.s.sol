// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20Decimals} from "src/mocks/MockERC20Decimals.sol";

contract DeployMockAsset is Script {
  function run() external {
    // Config from env with sensible defaults
    string memory name_ = vm.envOr("NAME", string("Mock USD Coin"));
    string memory symbol_ = vm.envOr("SYMBOL", string("mUSDC"));
    uint256 decU = vm.envOr("DECIMALS", uint256(6));
    require(decU <= type(uint8).max, "decimals");
    uint8 decimals_ = uint8(decU);

    address mintTo = vm.envOr("MINT_TO", address(0));
    uint256 mintAmount = vm.envOr("MINT_AMOUNT", uint256(0)); // raw units; if 0, default below

    vm.startBroadcast();
    MockERC20Decimals token = new MockERC20Decimals(name_, symbol_, decimals_);

    // Default mint: 1,000,000 units to broadcaster if no explicit target
    address defaultTo = mintTo == address(0) ? tx.origin : mintTo;
    uint256 defaultAmt = mintAmount == 0 ? (1_000_000 * (10 ** uint256(decimals_))) : mintAmount;
    token.mint(defaultTo, defaultAmt);
    vm.stopBroadcast();

    console2.log("MockAsset:", address(token));
    console2.log("Decimals:", decimals_);
    console2.log("Minted:", defaultAmt);
    console2.log("MintTo:", defaultTo);
  }
}

