// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SimpleVault4626Upgradeable} from "src/vault/SimpleVault4626Upgradeable.sol";
import {SimpleHoldingAdapter} from "src/adapter/SimpleHoldingAdapter.sol";
import {SimpleAaveAdapter} from "src/adapter/SimpleAaveAdapter.sol";
import {MockAutoYieldAdapter} from "src/adapter/MockAutoYieldAdapter.sol";
import {NGORegistrySimple} from "src/ngo/NGORegistrySimple.sol";
import {DonationPayer} from "src/ngo/DonationPayer.sol";
import {TreasurySimple} from "src/governance/TreasurySimple.sol";

contract DeployMVP is Script {
  struct VaultCfg {
    string name;
    string symbol;
    uint16 split;
    uint16 feeBps;
    uint256 tvlCap;
    uint256 harvestWindowBlocks;
  }

  function run() external {
    // Env
    address owner = vm.envAddress("OWNER");
    address guardian = vm.envAddress("GUARDIAN");
    address asset = vm.envAddress("ASSET"); // e.g., USDC on Base Sepolia/Mainnet
    address ngoMgr = vm.envOr("NGO_MANAGER", owner);

    // Choose adapter type
    bool useAave = vm.envOr("USE_AAVE", false);
    bool useMockYield = vm.envOr("USE_MOCK_YIELD", false);
    address aToken = vm.envOr("ATOKEN", address(0));
    address aavePool = vm.envOr("AAVE_POOL", address(0));
    uint256 mockYieldRate = vm.envOr("YIELD_RATE_WAD", uint256(1e9)); // ~3.15% APR by default

    // Preflight checks
    console2.log("chainId:", block.chainid);
    // Validate asset looks like an ERC20 by probing decimals, and compute tvl cap units by decimals
    uint8 assetDecimals;
    try IERC20Metadata(asset).decimals() returns (uint8 dec) {
      assetDecimals = dec;
      console2.log("asset.decimals:", uint256(dec));
    } catch {
      revert("ASSET is not ERC20 metadata-compatible (decimals)");
    }
    uint256 tvlCapUnits = 1_000_000 * (10 ** uint256(assetDecimals));

    // Start broadcasting from the deployer EOA (from PRIVATE_KEY CLI/env)
    vm.startBroadcast();
    address deployer = tx.origin; // the EOA sending txs after startBroadcast
    // Core components
    TreasurySimple treasury = new TreasurySimple(owner);
    // Own DonationPayer by deployer during wiring; hand over to OWNER after
    DonationPayer payer = new DonationPayer(deployer);
    NGORegistrySimple regImpl = new NGORegistrySimple(owner, ngoMgr);
    NGORegistrySimple registry = NGORegistrySimple(address(regImpl)); // upgradeable pattern ready if needed later

    // Proxy admin (owned by current broadcaster; recommended to be OWNER key)
    ProxyAdmin admin = new ProxyAdmin(owner);

    // Adapters (one per vault)
    address[3] memory adapters;
    for (uint256 i = 0; i < 3; ++i) {
      if (useAave) {
        adapters[i] = address(new SimpleAaveAdapter(asset, aToken, aavePool, address(0)));
      } else if (useMockYield) {
        adapters[i] = address(new MockAutoYieldAdapter(asset, address(0), mockYieldRate));
      } else {
        adapters[i] = address(new SimpleHoldingAdapter(asset, address(0)));
      }
    }

    // Vault implementation
    SimpleVault4626Upgradeable impl = new SimpleVault4626Upgradeable();

    VaultCfg[3] memory cfg = [
      VaultCfg({name: "GIVE-50", symbol: "G50", split: 5000, feeBps: 100, tvlCap: tvlCapUnits, harvestWindowBlocks: 20}),
      VaultCfg({name: "GIVE-75", symbol: "G75", split: 7500, feeBps: 100, tvlCap: tvlCapUnits, harvestWindowBlocks: 20}),
      VaultCfg({name: "GIVE-100", symbol: "G100", split: 10_000, feeBps: 100, tvlCap: tvlCapUnits, harvestWindowBlocks: 20})
    ];

    address[3] memory vaults;
    for (uint256 i = 0; i < 3; ++i) {
      bytes memory init = abi.encodeWithSelector(
        SimpleVault4626Upgradeable.initialize.selector,
        IERC20(asset), cfg[i].name, cfg[i].symbol,
        adapters[i], address(treasury), address(payer), address(registry), owner, guardian,
        cfg[i].split, cfg[i].feeBps, cfg[i].tvlCap, cfg[i].harvestWindowBlocks
      );
      TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(admin), init);
      vaults[i] = address(proxy);
      console2.log("Vault", i, vaults[i]);
    }

    // finalize adapter -> vault wiring
    for (uint256 i = 0; i < 3; ++i) {
      if (useAave) {
        SimpleAaveAdapter(adapters[i]).setVault(vaults[i]);
      } else if (useMockYield) {
        MockAutoYieldAdapter(adapters[i]).setVault(vaults[i]);
      } else {
        SimpleHoldingAdapter(adapters[i]).setVault(vaults[i]);
      }
    }

    // authorize payer for all vaults (requires payer owner = broadcaster)
    for (uint256 i = 0; i < 3; ++i) {
      payer.setAuthorizedCaller(vaults[i], true);
    }

    // hand off DonationPayer ownership to final OWNER
    payer.setOwner(owner);

    vm.stopBroadcast();

    console2.log("Treasury:", address(treasury));
    console2.log("DonationPayer:", address(payer));
    console2.log("NGORegistry:", address(registry));
    console2.log("ProxyAdmin:", address(admin));
    console2.log("Adapter0:", adapters[0]);
    console2.log("Adapter1:", adapters[1]);
    console2.log("Adapter2:", adapters[2]);
    console2.log("Vault50:", vaults[0]);
    console2.log("Vault75:", vaults[1]);
    console2.log("Vault100:", vaults[2]);
  }
}
