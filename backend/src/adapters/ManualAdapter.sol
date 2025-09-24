// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IYieldAdapter} from "../interfaces/IYieldAdapter.sol";
import {IConfigurableAdapter} from "../vault/IConfigurableAdapter.sol";
import {Errors} from "../utils/Errors.sol";
import {RoleAware} from "../access/RoleAware.sol";

/**
 * @title ManualAdapter
 * @dev Yield adapter that supports off-chain, manually managed strategies.
 * @notice Assets can be moved by a designated operator to another chain and returned with yield.
 */
contract ManualAdapter is IYieldAdapter, IConfigurableAdapter, RoleAware, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // === Cached roles ===
    bytes32 public immutable STRATEGY_ADMIN_ROLE;
    bytes32 public immutable GUARDIAN_ROLE;

    // === Core state ===
    IERC20 public immutable override asset;
    address public override vault;

    uint256 public totalInvested;
    uint256 public totalHarvested;
    uint256 public totalReportedLosses;

    event ManualTransfer(address indexed operator, address indexed to, uint256 amount);
    event LossReported(address indexed operator, uint256 amount);

    constructor(address roleManager_, address asset_, address vault_) RoleAware(roleManager_) {
        if (roleManager_ == address(0) || asset_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        STRATEGY_ADMIN_ROLE = roleManager.ROLE_STRATEGY_ADMIN();
        GUARDIAN_ROLE = roleManager.ROLE_GUARDIAN();

        asset = IERC20(asset_);
        vault = vault_; // Can be zero initially, will be set via configureForVault
    }

    /**
     * @dev Configures the adapter for a specific vault
     * @param _vault The vault address to configure
     */
    function configureForVault(address _vault) external override {
        require(vault == address(0) || vault == _vault, "ManualAdapter: Already configured");
        require(_vault != address(0), "ManualAdapter: Invalid vault");
        vault = _vault;
    }

    modifier onlyVault() {
        if (vault == address(0) || msg.sender != vault) revert Errors.OnlyVault();
        _;
    }

    modifier onlyStrategyOperator() {
        if (!roleManager.hasRole(STRATEGY_ADMIN_ROLE, msg.sender)) {
            revert Errors.UnauthorizedManager();
        }
        _;
    }

    // === IYieldAdapter implementation ===

    function totalAssets() external view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function invest(uint256 assets) external override onlyVault nonReentrant {
        if (assets == 0) revert Errors.InvalidInvestAmount();
        if (asset.balanceOf(address(this)) < assets) revert Errors.InsufficientBalance();

        totalInvested += assets;
        emit Invested(assets);
    }

    function divest(uint256 assets) external override onlyVault nonReentrant returns (uint256 returned) {
        if (assets == 0) revert Errors.InvalidDivestAmount();

        uint256 balance = asset.balanceOf(address(this));
        if (balance == 0) return 0;

        returned = assets > balance ? balance : assets;
        if (returned > 0) {
            asset.safeTransfer(vault, returned);
        }

        if (returned >= totalInvested) {
            totalInvested = 0;
        } else {
            totalInvested -= returned;
        }

        emit Divested(assets, returned);
    }

    function harvest() external override onlyVault nonReentrant returns (uint256 profit, uint256 loss) {
        uint256 currentBalance = asset.balanceOf(address(this));

        if (currentBalance > totalInvested) {
            profit = currentBalance - totalInvested;
            asset.safeTransfer(vault, profit);
            totalInvested = currentBalance - profit;
            totalHarvested += profit;
        } else if (currentBalance < totalInvested) {
            loss = totalInvested - currentBalance;
            totalInvested = currentBalance;
        }

        emit Harvested(profit, loss);
    }

    function emergencyWithdraw() external override nonReentrant returns (uint256 returned) {
        if (msg.sender != vault && !roleManager.hasRole(GUARDIAN_ROLE, msg.sender)) {
            revert Errors.UnauthorizedCaller(msg.sender);
        }

        returned = asset.balanceOf(address(this));
        if (returned > 0) {
            asset.safeTransfer(vault, returned);
        }

        if (returned >= totalInvested) {
            totalInvested = 0;
        } else {
            totalInvested -= returned;
        }

        emit EmergencyWithdraw(returned);
    }

    // === Manual operations ===

    /**
     * @notice Sends assets to an off-chain operator for manual yield generation.
     * @param to Destination address (e.g., bridge custodian).
     * @param amount Amount of tokens to transfer.
     */
    function manualTransfer(address to, uint256 amount) external nonReentrant onlyStrategyOperator {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();

        asset.safeTransfer(to, amount);
        emit ManualTransfer(msg.sender, to, amount);
    }

    /**
     * @notice Reports a realized loss when funds cannot be recovered off-chain.
     * @param amount Amount of loss to account for.
     */
    function reportLoss(uint256 amount) external onlyStrategyOperator {
        if (amount == 0) revert Errors.InvalidAmount();
        if (amount > totalInvested) revert Errors.InvalidAmount();

        totalInvested -= amount;
        totalReportedLosses += amount;
        emit LossReported(msg.sender, amount);
    }
}
