// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IYieldAdapter.sol";
import "../vault/IConfigurableAdapter.sol";
import "../utils/Errors.sol";
import "../access/RoleAware.sol";

// Aave V3 interfaces
interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveData(address asset) external view returns (ReserveData memory);
}

interface IAToken {
    function balanceOf(address user) external view returns (uint256);
    function scaledBalanceOf(address user) external view returns (uint256);
}

struct ReserveData {
    uint256 configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

/**
 * @title AaveAdapter
 * @dev Yield adapter for Aave V3 protocol (supply-only)
 * @notice Supplies assets to Aave and tracks yield through aToken balance changes
 */
contract AaveAdapter is IYieldAdapter, IConfigurableAdapter, RoleAware, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // === Cached roles ===
    bytes32 public immutable STRATEGY_ADMIN_ROLE;
    bytes32 public immutable GUARDIAN_ROLE;
    bytes32 public immutable VAULT_OPS_ROLE;
    uint256 public constant BASIS_POINTS = 10000;
    uint16 public constant AAVE_REFERRAL_CODE = 0;

    // === State Variables ===
    IERC20 public immutable override asset;
    address public override vault;
    IPool public immutable aavePool;
    IAToken public immutable aToken;

    uint256 public totalInvested;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public cumulativeYield;

    // Risk parameters
    uint256 public maxSlippageBps = 100; // 1%
    uint256 public emergencyExitBps = 9500; // 95% - allow 5% slippage in emergency

    bool public emergencyMode;

    // === Events ===
    event MaxSlippageUpdated(uint256 oldBps, uint256 newBps);
    event EmergencyExitBpsUpdated(uint256 oldBps, uint256 newBps);
    event EmergencyModeActivated(bool activated);
    event YieldAccrued(uint256 amount, uint256 newBalance);

    // === Constructor ===
    constructor(address roleManager_, address _asset, address _vault, address _aavePool) RoleAware(roleManager_) {
        if (_asset == address(0) || _aavePool == address(0)) {
            revert Errors.ZeroAddress();
        }

        asset = IERC20(_asset);
        vault = _vault; // Can be zero initially, will be set via configureForVault
        aavePool = IPool(_aavePool);

        // Get aToken address from Aave pool
        ReserveData memory reserveData = aavePool.getReserveData(_asset);
        if (reserveData.aTokenAddress == address(0)) {
            revert Errors.InvalidAsset();
        }
        aToken = IAToken(reserveData.aTokenAddress);

        STRATEGY_ADMIN_ROLE = roleManager.ROLE_STRATEGY_ADMIN();
        GUARDIAN_ROLE = roleManager.ROLE_GUARDIAN();
        VAULT_OPS_ROLE = roleManager.ROLE_VAULT_OPS();

        lastHarvestTime = block.timestamp;

        // Approve Aave pool to spend our tokens
        IERC20(asset).forceApprove(_aavePool, type(uint256).max);
    }

    /**
     * @dev Configures the adapter for a specific vault
     * @param _vault The vault address to configure
     */
    function configureForVault(address _vault) external override {
        require(vault == address(0) || vault == _vault, "AaveAdapter: Already configured");
        require(_vault != address(0), "AaveAdapter: Invalid vault");
        vault = _vault;
    }

    // === Modifiers ===
    modifier onlyVault() {
        if (vault == address(0) || msg.sender != vault) revert Errors.OnlyVault();
        _;
    }

    modifier whenNotEmergency() {
        if (emergencyMode) revert Errors.AdapterPaused();
        _;
    }

    // === IYieldAdapter Implementation ===

    /**
     * @dev Returns total assets under management (aToken balance)
     */
    function totalAssets() external view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /**
     * @dev Invests assets into Aave by supplying to the pool
     * @param assets Amount of assets to invest
     */
    function invest(uint256 assets) external override onlyVault nonReentrant whenNotPaused whenNotEmergency {
        if (assets == 0) revert Errors.InvalidInvestAmount();

        uint256 balanceBefore = asset.balanceOf(address(this));
        if (balanceBefore < assets) revert Errors.InsufficientBalance();

        // Supply to Aave
        aavePool.supply(address(asset), assets, address(this), AAVE_REFERRAL_CODE);

        totalInvested += assets;

        emit Invested(assets);
    }

    /**
     * @dev Divests assets from Aave by withdrawing from the pool
     * @param assets Amount of assets to divest
     * @return returned Actual amount of assets returned
     */
    function divest(uint256 assets) external override onlyVault nonReentrant whenNotPaused returns (uint256 returned) {
        if (assets == 0) revert Errors.InvalidDivestAmount();

        uint256 aTokenBalance = aToken.balanceOf(address(this));
        if (aTokenBalance == 0) return 0;

        // Withdraw from Aave (use type(uint256).max to withdraw all if needed)
        uint256 toWithdraw = assets > aTokenBalance ? type(uint256).max : assets;

        uint256 balanceBefore = asset.balanceOf(address(this));
        returned = aavePool.withdraw(address(asset), toWithdraw, address(this));

        // Verify we received the expected amount (within slippage tolerance)
        if (!emergencyMode && returned < assets) {
            uint256 slippage = ((assets - returned) * BASIS_POINTS) / assets;
            if (slippage > maxSlippageBps) {
                revert Errors.SlippageExceeded(slippage, maxSlippageBps);
            }
        }

        // Update total invested
        if (returned <= totalInvested) {
            totalInvested -= returned;
        } else {
            totalInvested = 0;
        }

        // Transfer the withdrawn assets back to the vault
        if (returned > 0) {
            IERC20(asset).safeTransfer(vault, returned);
        }

        emit Divested(assets, returned);
    }

    /**
     * @dev Harvests yield by calculating aToken balance increase
     * @return profit Amount of profit harvested
     * @return loss Amount of loss incurred (should be 0 for Aave)
     */
    function harvest() external override onlyVault nonReentrant whenNotPaused returns (uint256 profit, uint256 loss) {
        uint256 currentBalance = aToken.balanceOf(address(this));

        if (currentBalance > totalInvested) {
            profit = currentBalance - totalInvested;

            // Withdraw the profit
            if (profit > 0) {
                uint256 withdrawn = aavePool.withdraw(address(asset), profit, vault);
                profit = withdrawn; // Use actual withdrawn amount

                // Update totalInvested to reflect the withdrawn profit
                totalInvested = currentBalance - profit;

                cumulativeYield += profit;
                totalHarvested += profit;
            }
        } else if (currentBalance < totalInvested) {
            // This shouldn't happen with Aave supply-only, but handle it
            loss = totalInvested - currentBalance;
            totalInvested = currentBalance;
        }

        lastHarvestTime = block.timestamp;

        emit Harvested(profit, loss);
        if (profit > 0) {
            emit YieldAccrued(profit, currentBalance);
        }
    }

    /**
     * @dev Emergency withdrawal of all assets
     * @return returned Amount of assets returned
     */
    function emergencyWithdraw() external override nonReentrant returns (uint256 returned) {
        if (
            msg.sender != vault && !roleManager.hasRole(GUARDIAN_ROLE, msg.sender)
                && !roleManager.hasRole(VAULT_OPS_ROLE, msg.sender)
        ) {
            revert Errors.UnauthorizedCaller(msg.sender);
        }
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        if (aTokenBalance == 0) return 0;

        // Activate emergency mode
        emergencyMode = true;

        // Withdraw all available assets (use aToken balance to avoid overflow)
        returned = aavePool.withdraw(address(asset), aTokenBalance, vault);

        // Reset state
        totalInvested = 0;

        emit EmergencyWithdraw(returned);
        emit EmergencyModeActivated(true);
    }

    // === Admin Functions ===

    /**
     * @dev Sets maximum slippage tolerance
     * @param _bps Basis points (100 = 1%)
     */
    function setMaxSlippageBps(uint256 _bps) external onlyRole(STRATEGY_ADMIN_ROLE) {
        if (_bps > 1000) revert Errors.InvalidSlippageBps(); // Max 10%

        uint256 oldBps = maxSlippageBps;
        maxSlippageBps = _bps;

        emit MaxSlippageUpdated(oldBps, _bps);
    }

    /**
     * @dev Sets emergency exit slippage tolerance
     * @param _bps Basis points (9500 = 95%)
     */
    function setEmergencyExitBps(uint256 _bps) external onlyRole(STRATEGY_ADMIN_ROLE) {
        if (_bps < 5000 || _bps > 10000) revert Errors.ParameterOutOfRange();

        uint256 oldBps = emergencyExitBps;
        emergencyExitBps = _bps;

        emit EmergencyExitBpsUpdated(oldBps, _bps);
    }

    /**
     * @dev Deactivates emergency mode
     */
    function deactivateEmergencyMode() external onlyRole(STRATEGY_ADMIN_ROLE) {
        emergencyMode = false;
        emit EmergencyModeActivated(false);
    }

    /**
     * @dev Pauses the adapter
     */
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the adapter
     */
    function unpause() external onlyRole(STRATEGY_ADMIN_ROLE) {
        _unpause();
    }

    // === View Functions ===

    /**
     * @dev Returns current yield rate from Aave
     */
    function getCurrentYieldRate() external view returns (uint256) {
        ReserveData memory reserveData = aavePool.getReserveData(address(asset));
        return reserveData.currentLiquidityRate;
    }

    /**
     * @dev Returns adapter statistics
     */
    function getAdapterStats()
        external
        view
        returns (
            uint256 totalInvestedAmount,
            uint256 totalHarvestedAmount,
            uint256 cumulativeYieldAmount,
            uint256 lastHarvest,
            uint256 currentBalance
        )
    {
        return (totalInvested, totalHarvested, cumulativeYield, lastHarvestTime, aToken.balanceOf(address(this)));
    }

    /**
     * @dev Returns risk parameters
     */
    function getRiskParameters() external view returns (uint256 maxSlippage, uint256 emergencyExit, bool emergency) {
        return (maxSlippageBps, emergencyExitBps, emergencyMode);
    }

    /**
     * @dev Returns Aave-specific information
     */
    function getAaveInfo()
        external
        view
        returns (address poolAddress, address aTokenAddress, uint256 liquidityRate, uint256 aTokenBalance)
    {
        ReserveData memory reserveData = aavePool.getReserveData(address(asset));
        return (address(aavePool), address(aToken), reserveData.currentLiquidityRate, aToken.balanceOf(address(this)));
    }

    /**
     * @dev Checks if the adapter is healthy
     */
    function isHealthy() external view returns (bool) {
        if (emergencyMode || paused()) return false;

        // Check if Aave reserve is active and not frozen
        try aavePool.getReserveData(address(asset)) returns (ReserveData memory data) {
            // Basic health check - reserve exists and has aToken
            return data.aTokenAddress != address(0);
        } catch {
            return false;
        }
    }
}
