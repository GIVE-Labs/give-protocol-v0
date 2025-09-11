// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {StrategyManager} from "src/vault/StrategyManager.sol";
import {GiveVault4626} from "src/vault/GiveVault4626.sol";
import {NGORegistry} from "src/donation/NGORegistry.sol";
import {DonationRouter} from "src/donation/DonationRouter.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DeploySepolia is Script {
  function run() external {
    // Required env vars:
    // PRIVATE_KEY: deployer PK
    // ASSET_ADDRESS: ERC20 underlying asset on Sepolia
    // TREASURY_ADDRESS: treasury recipient
    // ADMIN_ADDRESS: admin for roles
    // NGO_MANAGER_ADDRESS: NGO manager role
    // STRATEGY_MANAGER_ADDRESS: strategy manager role
    uint256 pk = vm.envUint("PRIVATE_KEY");
    address assetAddr = vm.envAddress("ASSET_ADDRESS");
    address treasury = vm.envAddress("TREASURY_ADDRESS");
    address admin = vm.envAddress("ADMIN_ADDRESS");
    address ngoMgr = vm.envAddress("NGO_MANAGER_ADDRESS");
    address stratMgrRole = vm.envAddress("STRATEGY_MANAGER_ADDRESS");

    vm.startBroadcast(pk);

    StrategyManager sm = new StrategyManager(admin, stratMgrRole);
    GiveVault4626 vault = new GiveVault4626(ERC20(assetAddr), "GiveVault", "GV", address(sm), treasury, 100, 10);
    NGORegistry reg = new NGORegistry(admin, ngoMgr);
    DonationRouter router = new DonationRouter(address(vault), address(reg), admin);

    console2.log("StrategyManager:", address(sm));
    console2.log("Vault:", address(vault));
    console2.log("NGORegistry:", address(reg));
    console2.log("DonationRouter:", address(router));

    vm.stopBroadcast();
  }
}
