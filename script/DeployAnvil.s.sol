// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {StrategyManager} from "src/vault/StrategyManager.sol";
import {GiveVault4626} from "src/vault/GiveVault4626.sol";
import {NGORegistry} from "src/donation/NGORegistry.sol";
import {DonationRouter} from "src/donation/DonationRouter.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DeployAnvil is Script {
  function run() external {
    uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
    if (pk == 0) {
      // Default Anvil first account private key
      pk = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    }
    address deployer = vm.addr(pk);
    vm.startBroadcast(pk);

    // 1) Asset (mock) & roles
    MockERC20 asset = new MockERC20("Mock Asset", "MA");
    address admin = deployer;
    address strategyMgrRole = deployer;
    address treasury = deployer;

    // 2) StrategyManager
    StrategyManager sm = new StrategyManager(admin, strategyMgrRole);

    // 3) Vault
    GiveVault4626 vault = new GiveVault4626(ERC20(address(asset)), "GiveVault", "GV", address(sm), treasury, 100, 10);

    // 4) NGO Registry + Router
    NGORegistry reg = new NGORegistry(admin, admin);
    DonationRouter router = new DonationRouter(address(vault), address(reg), admin);

    console2.log("Deployer:", deployer);
    console2.log("Asset:", address(asset));
    console2.log("StrategyManager:", address(sm));
    console2.log("Vault:", address(vault));
    console2.log("NGORegistry:", address(reg));
    console2.log("DonationRouter:", address(router));

    vm.stopBroadcast();
  }
}
