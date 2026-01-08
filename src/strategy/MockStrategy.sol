// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "src/BankV4.sol";

/*//////////////////////////////////////////////////////////////
                        MOCK STRATEGY
//////////////////////////////////////////////////////////////*/

/**
 * @title MockStrategy
 * @notice Minimal external strategy for testing ERC4626 vaults
 *
 * @dev Properties:
 *  - Assets are fully custodied by this contract
 *  - totalAssets() reflects internal accounting, not token balance
 *  - Supports manual gain/loss simulation
 *  - Withdrawals revert on insufficient liquidity
 *
 * Trust model:
 *  - Vault trusts totalAssets()
 *  - Strategy does not mint or burn tokens
 *  - Insolvency is explicit and testable
 */

contract MockStrategy is IStrategy {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC20 asset managed by this strategy
    IERC20 public immutable asset;

    /// @notice Vault authorized to interact with this strategy
    address public vault;

    /// @notice Internal accounting of managed assets
    uint256 public managedAssets;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error MockStrategy__NotVault();
    error MockStrategy__ZeroAssets();
    error MockStrategy__InsufficientAssets();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(uint256 assets);
    event Withdrawn(uint256 assets);
    event GainSimulated(uint256 amount);
    event LossSimulated(uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyVault() {
        if (msg.sender != vault) revert MockStrategy__NotVault();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        ONE-TIME SETTER
    //////////////////////////////////////////////////////////////*/

    function setVault(address vault_) external {
        require(vault == address(0), "VAULT_ALREADY_SET");
        vault = vault_;
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into the strategy
     * @dev Tokens must already be transferred before calling
     */
    function deposit(uint256 assets) external onlyVault {
        if (assets == 0) revert MockStrategy__ZeroAssets();

        managedAssets += assets;
        emit Deposited(assets);
    }

    /**
     * @notice Withdraw assets back to the vault
     * @dev Reverts if insufficient liquidity
     */
    function withdraw(uint256 assets) external onlyVault {
        if (assets == 0) revert MockStrategy__ZeroAssets();
        if (assets > managedAssets) revert MockStrategy__InsufficientAssets();

        managedAssets -= assets;
        asset.safeTransfer(vault, assets);

        emit Withdrawn(assets);
    }

    /**
     * @notice Total assets managed by the strategy
     * @dev Trusted by the vault
     */
    function totalAssets() external view returns (uint256) {
        return managedAssets;
    }

    /*//////////////////////////////////////////////////////////////
                        TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Simulate strategy profit
     * @dev Assets must be transferred in manually before calling
     */
    function simulateGain(uint256 amount) external {
        if (amount == 0) revert MockStrategy__ZeroAssets();

        managedAssets += amount;
        emit GainSimulated(amount);
    }

    /**
     * @notice Simulate strategy loss
     * @dev Does NOT transfer tokens out — creates accounting insolvency
     */
    function simulateLoss(uint256 amount) external {
        if (amount == 0) revert MockStrategy__ZeroAssets();
        if (amount > managedAssets) revert MockStrategy__InsufficientAssets();

        managedAssets -= amount;
        emit LossSimulated(amount);
    }
}
