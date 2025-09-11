// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// import {Script} from "forge-std/Script.sol"; // to be enabled after installing forge-std

/// @notice Placeholder deploy script for core contracts wiring
contract DeployCore /* is Script */ {
  function run() external {
    // vm.startBroadcast();
    // Deploy ACL, EmergencyController, NGORegistry, StrategyManager, Treasury
    // Deploy GiveProtocolCore (implementation), then proxy, then wire modules
    // vm.stopBroadcast();
  }
}

