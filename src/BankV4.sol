// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/*//////////////////////////////////////////////////////////////
                            STRATEGY
//////////////////////////////////////////////////////////////*/

interface IStrategy {
    function deposit(uint256 assets) external;
    function withdraw(uint256 assets) external;
    function totalAssets() external view returns (uint256);
}

/*//////////////////////////////////////////////////////////////
                            BANK V4
//////////////////////////////////////////////////////////////*/

/**
 * @title BankV4
 * @notice ERC4626 vault with external strategy integration
 *
 * @dev Key properties:
 *  - ERC4626 preview/execution parity preserved
 *  - Assets may be partially or fully deployed externally
 *  - Strategy gains/losses are socialized via PPS
 *  - No auto-deployment on deposit
 *  - No hidden share minting or burning
 *
 * Trust model:
 *  - Strategy is trusted to honestly report totalAssets()
 *  - Strategy insolvency is surfaced via reverts
 */
contract BankV4 is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice External strategy controlled by this vault
    IStrategy public immutable strategy;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BankV4__ZeroAssets();
    error BankV4__InsufficientIdleAssets();
    error BankV4__InsufficientStrategyLiquidity();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when assets are deployed into the strategy
    event StrategyDeployed(uint256 assets);

    /// @notice Emitted when assets are manually withdrawn from strategy
    event StrategyWithdrawn(uint256 assets);

    /// @notice Emitted when a user withdrawal triggers strategy unwinding
    event StrategyWithdrawalTriggered(uint256 shortfall);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IERC20 asset_, IStrategy strategy_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        strategy = strategy_;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total assets managed by the vault
     * @dev Includes both idle vault balance and strategy balance
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + strategy.totalAssets();
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy idle vault assets into the strategy
     * @dev Operational function. No shares are minted or burned.
     */
    function deployToStrategy(uint256 assets) external nonReentrant {
        if (assets == 0) revert BankV4__ZeroAssets();

        IERC20 token = IERC20(asset());
        uint256 idleAssets = token.balanceOf(address(this));

        if (assets > idleAssets) revert BankV4__InsufficientIdleAssets();

        token.safeTransfer(address(strategy), assets);
        strategy.deposit(assets);

        emit StrategyDeployed(assets);
    }

    /**
     * @notice Withdraw assets from the strategy back into the vault
     * @dev Reverts if strategy cannot return full amount
     */
    function withdrawFromStrategy(uint256 assets) external nonReentrant {
        if (assets == 0) revert BankV4__ZeroAssets();

        IERC20 token = IERC20(asset());
        uint256 balanceBefore = token.balanceOf(address(this));

        strategy.withdraw(assets);

        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter - balanceBefore != assets) {
            revert BankV4__InsufficientStrategyLiquidity();
        }

        emit StrategyWithdrawn(assets);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW OVERRIDE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures sufficient idle liquidity by unwinding strategy
     *      positions before executing ERC4626 withdrawal.
     *
     * IMPORTANT:
     *  - super._withdraw MUST always be called
     *  - Preview math remains untouched
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        IERC20 token = IERC20(asset());
        uint256 idleAssets = token.balanceOf(address(this));

        if (idleAssets < assets) {
            uint256 shortfall = assets - idleAssets;
            emit StrategyWithdrawalTriggered(shortfall);

            uint256 beforeBal = idleAssets;
            strategy.withdraw(shortfall);
            uint256 afterBal = token.balanceOf(address(this));

            if (afterBal - beforeBal != shortfall) {
                revert BankV4__InsufficientStrategyLiquidity();
            }
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }
}
