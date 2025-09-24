// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {RoleManager} from "../src/access/RoleManager.sol";
import {CampaignRegistry} from "../src/campaign/CampaignRegistry.sol";
import {StrategyRegistry} from "../src/manager/StrategyRegistry.sol";
import {PayoutRouter} from "../src/payout/PayoutRouter.sol";
import {CampaignVaultFactory} from "../src/vault/CampaignVaultFactory.sol";
import {VaultDeploymentLib} from "../src/vault/VaultDeploymentLib.sol";
import {ManagerDeploymentLib} from "../src/vault/ManagerDeploymentLib.sol";
import {StrategyManager} from "../src/manager/StrategyManager.sol";
import {CampaignVault} from "../src/vault/CampaignVault.sol";
import {GiveVault4626} from "../src/vault/GiveVault4626.sol";
import {AaveAdapter} from "../src/adapters/AaveAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ManualAdapter} from "../src/adapters/ManualAdapter.sol";
import {RegistryTypes} from "../src/manager/RegistryTypes.sol";

/**
 * @dev Comprehensive deployment script for Scroll Mainnet.
 *      Configured for Nanyang Press Foundation campaign with Aave USDC adapter.
 */
contract DeployScroll is Script {
    // Protocol administration - using deployer as initial admin
    address internal SCROLL_MULTISIG; // Will be set from deployer

    // === External addresses on Scroll Mainnet ===
    address internal constant USDC = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4; // Scroll USDC.e
    address internal constant WETH = 0x5300000000000000000000000000000000000004; // Scroll WETH
    address internal constant AAVE_POOL = 0x11fCfe756c05AD438e312a7fd934381537D3cFfe; // Aave V3 Pool on Scroll

    // Treasury & payout configuration
    address internal PROTOCOL_TREASURY; // Will be set from deployer initially
    address internal PROTOCOL_GUARDIAN; // Will be set from deployer initially

    // Nanyang Press Foundation campaign configuration
    address internal constant NPF_CURATOR = 0x98cF137F0d8F2C72F22fa44Ec1076D27ab0cd245; // Nanyang Press Foundation curator address
    address internal constant NPF_PAYOUT = 0x98cF137F0d8F2C72F22fa44Ec1076D27ab0cd245; // Nanyang Press Foundation beneficiary wallet

    // Strategy metadata URIs
    string internal constant USDC_STRATEGY_URI = "ipfs://QmAaveUSDCConservativeStrategy"; // Update with actual IPFS
    string internal constant WETH_STRATEGY_URI = "ipfs://QmAaveWETHModerateStrategy"; // Update with actual IPFS
    string internal constant MANUAL_STRATEGY_URI = "ipfs://QmManualOffChainStrategy"; // Update with actual IPFS

    uint256 internal constant MAX_TVL_DEFAULT = type(uint256).max;

    struct Deployment {
        address roleManager;
        address strategyRegistry;
        address campaignRegistry;
        address payoutRouter;
        address vaultFactory;
        address usdcAdapter;
        address wethAdapter;
        address manualAdapter;
        uint64 usdcStrategyId;
        uint64 wethStrategyId;
        uint64 manualStrategyId;
        uint64 campaignId;
        address vault;
        address strategyManager;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Use deployer as initial admin, can be transferred later
        SCROLL_MULTISIG = deployer;
        PROTOCOL_TREASURY = deployer;
        PROTOCOL_GUARDIAN = deployer;

        vm.startBroadcast(deployerKey);

        Deployment memory out;

        RoleManager roleManager = new RoleManager(SCROLL_MULTISIG);
        out.roleManager = address(roleManager);

        // Grant critical roles
        roleManager.grantRole(roleManager.ROLE_GUARDIAN(), PROTOCOL_GUARDIAN);
        roleManager.grantRole(roleManager.ROLE_STRATEGY_ADMIN(), SCROLL_MULTISIG);
        roleManager.grantRole(roleManager.ROLE_TREASURY(), PROTOCOL_TREASURY);
        roleManager.grantRole(roleManager.ROLE_CAMPAIGN_ADMIN(), SCROLL_MULTISIG);
        roleManager.grantRole(roleManager.ROLE_VAULT_OPS(), SCROLL_MULTISIG);

        StrategyRegistry strategyRegistry = new StrategyRegistry(address(roleManager));
        out.strategyRegistry = address(strategyRegistry);

        CampaignRegistry campaignRegistry = new CampaignRegistry(
            address(roleManager),
            PROTOCOL_TREASURY,
            address(strategyRegistry),
            0 // minimum stake, update if needed
        );
        out.campaignRegistry = address(campaignRegistry);

        PayoutRouter payoutRouter = new PayoutRouter(
            address(roleManager),
            address(campaignRegistry),
            PROTOCOL_TREASURY
        );
        out.payoutRouter = address(payoutRouter);

        // Deploy helper contracts first
        VaultDeploymentLib vaultDeployer = new VaultDeploymentLib();
        ManagerDeploymentLib managerDeployer = new ManagerDeploymentLib();

        // Grant roles to helper contracts
        roleManager.grantRole(roleManager.DEFAULT_ADMIN_ROLE(), address(managerDeployer));
        roleManager.grantRole(roleManager.ROLE_STRATEGY_ADMIN(), address(managerDeployer));
        roleManager.grantRole(roleManager.ROLE_CAMPAIGN_ADMIN(), address(managerDeployer));

        // Deploy factory with helper contract references
        CampaignVaultFactory vaultFactory = new CampaignVaultFactory(
            address(roleManager),
            address(strategyRegistry),
            address(campaignRegistry),
            address(payoutRouter),
            address(vaultDeployer),
            address(managerDeployer)
        );
        out.vaultFactory = address(vaultFactory);

        // Allow factory to administer campaign approvals/strategy approvals if needed
        roleManager.grantRole(roleManager.ROLE_CAMPAIGN_ADMIN(), address(vaultFactory));
        roleManager.grantRole(roleManager.ROLE_STRATEGY_ADMIN(), address(vaultFactory));
        roleManager.grantRole(roleManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));

        // === Deploy adapters ===
        // Deploy Aave USDC adapter for Nanyang Press Foundation
        AaveAdapter usdcAdapter = new AaveAdapter(
            address(roleManager),
            USDC,
            address(0), // will be configured when vault is deployed
            AAVE_POOL
        );
        out.usdcAdapter = address(usdcAdapter);

        // Optional: Deploy WETH adapter for future campaigns
        AaveAdapter wethAdapter = new AaveAdapter(
            address(roleManager),
            WETH,
            address(0),
            AAVE_POOL
        );
        out.wethAdapter = address(wethAdapter);

        // Optional: Deploy manual adapter for off-chain strategies
        ManualAdapter manualAdapter = new ManualAdapter(
            address(roleManager),
            USDC,
            address(0)
        );
        out.manualAdapter = address(manualAdapter);

        // Register strategies
        out.usdcStrategyId = strategyRegistry.createStrategy(
            USDC,
            address(usdcAdapter),
            RegistryTypes.RiskTier.Conservative,
            USDC_STRATEGY_URI,
            MAX_TVL_DEFAULT
        );

        out.wethStrategyId = strategyRegistry.createStrategy(
            WETH,
            address(wethAdapter),
            RegistryTypes.RiskTier.Moderate,
            WETH_STRATEGY_URI,
            MAX_TVL_DEFAULT
        );

        out.manualStrategyId = strategyRegistry.createStrategy(
            USDC,
            address(manualAdapter),
            RegistryTypes.RiskTier.Experimental,
            MANUAL_STRATEGY_URI,
            MAX_TVL_DEFAULT
        );

        // === Create Nanyang Press Foundation Campaign ===
        console.log("Creating Nanyang Press Foundation campaign...");
        console.log("Beneficiary: Nanyang Press Foundation");
        console.log("Mission: Supporting independent journalism and press freedom in Southeast Asia");

        // Submit campaign for Nanyang Press Foundation
        uint64 campaignId = campaignRegistry.submitCampaign(
            "ipfs://QmNanyangPressFoundation2025", // Campaign metadata with foundation details
            NPF_CURATOR,  // Foundation curator managing the campaign
            NPF_PAYOUT,   // Foundation wallet receiving the yield donations
            RegistryTypes.LockProfile.Minutes1  // Using 1 minute lock for testing
        );
        out.campaignId = campaignId;

        // Approve campaign
        campaignRegistry.approveCampaign(campaignId);

        // Attach USDC Aave strategy to campaign
        campaignRegistry.attachStrategy(campaignId, out.usdcStrategyId);

        console.log("Deploying donation vault for Nanyang Press Foundation...");

        // Deploy vault for Nanyang Press Foundation campaign
        // This vault will collect USDC donations and generate yield through Aave
        // All yield goes to the foundation while donors keep their principal
        CampaignVaultFactory.Deployment memory deployment = vaultFactory.deployCampaignVault(
            campaignId,
            out.usdcStrategyId,
            RegistryTypes.LockProfile.Minutes1,  // Using 1 minute lock for testing
            "Nanyang Press Foundation Yield Vault",
            "NPF-USDC",
            1e6 // minimum deposit (1 USDC)
        );
        out.vault = deployment.vault;
        out.strategyManager = deployment.strategyManager;

        // Configure the deployed strategy manager
        StrategyManager manager = StrategyManager(deployment.strategyManager);
        manager.updateVaultParameters(100, 50, 50); // 1% buffer, 0.5% invest/divest thresholds

        // === Test Deposit and Withdrawal Flow ===
        console.log("\n--- Testing Deposit & Withdrawal Flow ---");

        // Get the vault instance
        CampaignVault vaultInstance = CampaignVault(payable(deployment.vault));

        // Check deployer's actual USDC balance (should already have USDC)
        uint256 initialBalance = IERC20(USDC).balanceOf(deployer);
        console.log("Deployer USDC balance:", initialBalance / 1e6, "USDC");

        require(initialBalance >= 1e6, "Deployer needs at least 1 USDC for testing");

        // Approve vault to spend 1 USDC
        IERC20(USDC).approve(address(vaultInstance), 1e6);
        console.log("Approved vault to spend 1 USDC");

        // Deposit 1 USDC
        uint256 depositAmount = 1e6; // 1 USDC
        uint256 sharesReceived = vaultInstance.deposit(depositAmount, deployer);
        console.log("Deposited 1 USDC");
        console.log("Shares received:", sharesReceived);

        // Check vault balance after deposit
        uint256 vaultBalance = vaultInstance.balanceOf(deployer);
        console.log("Vault share balance:", vaultBalance);

        // Get the unlock time
        uint256 unlockTime = vaultInstance.getNextUnlockTime(deployer);
        console.log("Position will unlock at timestamp:", unlockTime);
        console.log("Current timestamp:", block.timestamp);
        uint256 timeUntilUnlock = unlockTime - block.timestamp;
        console.log("Time until unlock (seconds):", timeUntilUnlock);

        // Wait 70 seconds (more than 1 minute lock period)
        console.log("\nWarping time forward 70 seconds...");
        vm.warp(block.timestamp + 70);
        console.log("New timestamp:", block.timestamp);

        // Check if position is unlocked
        uint256 unlockedShares = vaultInstance.getUnlockedShares(deployer);
        console.log("Unlocked shares available:", unlockedShares);

        // Withdraw the funds
        console.log("\nWithdrawing funds...");
        uint256 assetsRedeemed = vaultInstance.redeem(sharesReceived, deployer, deployer);
        console.log("Shares redeemed:", sharesReceived);
        console.log("USDC received:", assetsRedeemed / 1e6);

        // Check final balance
        uint256 finalBalance = IERC20(USDC).balanceOf(deployer);
        console.log("Final USDC balance (USDC):", finalBalance / 1e6);
        int256 netChange = int256(finalBalance) - int256(initialBalance);
        console.log("Net change (USDC):", uint256(netChange < 0 ? -netChange : netChange) / 1e6);

        // Verify withdrawal was successful
        require(vaultInstance.balanceOf(deployer) == 0, "Should have no shares left");
        console.log("SUCCESS: Test deposit and withdrawal completed!");

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("\n====== Deployment Complete ======");
        console.log("\n--- Core Infrastructure ---");
        console.log("RoleManager:", out.roleManager);
        console.log("StrategyRegistry:", out.strategyRegistry);
        console.log("CampaignRegistry:", out.campaignRegistry);
        console.log("PayoutRouter:", out.payoutRouter);
        console.log("VaultFactory:", out.vaultFactory);

        console.log("\n--- Yield Adapters ---");
        console.log("USDC Aave Adapter:", out.usdcAdapter);
        console.log("USDC Strategy ID:", out.usdcStrategyId);

        console.log("\n--- Nanyang Press Foundation Campaign ---");
        console.log("Campaign ID:", campaignId);
        console.log("Beneficiary: Nanyang Press Foundation");
        console.log("Beneficiary Wallet:", NPF_PAYOUT);
        console.log("Campaign Curator:", NPF_CURATOR);
        console.log("Donation Vault:", out.vault);
        console.log("Strategy Manager:", out.strategyManager);
        console.log("Asset: USDC (", USDC, ")");
        console.log("Yield Source: Aave V3 on Scroll");
        console.log("Lock Period: 1 minute (testing mode)");
        console.log("Min Deposit: 1 USDC");

        console.log("\n=================================");
        console.log("Supporters can now deposit USDC to:", out.vault);
        console.log("100% of yield will be donated to Nanyang Press Foundation");
        console.log("Supporters retain full principal, redeemable after 90 days");
        console.log("=================================");
    }
}
