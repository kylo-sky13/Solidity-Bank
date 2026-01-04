// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BankV2
 * @notice ERC20 token vault supporting multiple tokens with strict accounting.
 *
 * @dev
 * Scope:
 * - Direct ERC20 custody only
 * - No shares, no ERC4626
 * - No upgradeability
 * - Fee-on-transfer tokens explicitly rejected
 * - Rebasing and ERC777 tokens unsupported
 *
 * SECURITY MODEL:
 * - Exact per-user, per-token accounting
 * - Reentrancy-safe withdrawals
 * - Pause acts as a pure circuit breaker
 * - No admin fund access
 */
contract BankV2 is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev User => token => deposited amount
    mapping(address => mapping(address => uint256)) balances;

    /// @dev Token => total deposited across all users
    mapping(address => uint256) totalBalances;

    /// @notice Owner address with pause / unpause privileges only
    address public owner;

    /// @notice Global pause flag acting as a circuit breaker
    bool public paused;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when deploying with a zero owner address
    error BankV2__ZeroOwner();

    /// @notice Thrown when an action is attempted while paused
    error BankV2__Paused();

    /// @notice Thrown when caller is not the owner
    error BankV2__NotOwner();

    /// @notice Thrown when token address is invalid
    error BankV2__InvalidToken();

    /// @notice Thrown when transferred amount does not match requested amount
    error BankV2__FeeOnTransferDetected();

    /// @notice Thrown when amount is zero
    error BankV2__ZeroAmount();

    /// @notice Thrown when withdrawing more than available balance
    error BankV2__InsufficientFunds();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy the BankV2 vault
     * @param _owner Admin address with pause / unpause permissions
     *
     * @dev
     * - Owner has no ability to move funds
     * - No deposits occur during construction
     */
    constructor(address _owner) {
        if (_owner == address(0)) {
            revert BankV2__ZeroOwner();
        }
        owner = _owner;
        paused = false;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits tokens
    event Deposit(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when a user withdraws tokens
    event Withdraw(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when the vault is paused
    event Paused(address indexed caller);

    /// @notice Emitted when the vault is unpaused
    event Unpaused(address indexed caller);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Restricts function access to the owner
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert BankV2__NotOwner();
        }
        _;
    }

    /// @dev Prevents execution while the vault is paused
    modifier whenNotPaused() {
        if (paused) {
            revert BankV2__Paused();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause deposits and withdrawals
     *
     * @dev
     * - Acts as a circuit breaker
     * - Does not modify balances
     * - Callable only by the owner
     */
    function pause() external {
        if (msg.sender != owner) {
            revert BankV2__NotOwner();
        }
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause deposits and withdrawals
     *
     * @dev Callable only by the owner
     */
    function unpause() external {
        if (msg.sender != owner) {
            revert BankV2__NotOwner();
        }
        paused = false;
        emit Unpaused(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit ERC20 tokens into the vault
     * @param token ERC20 token address to deposit
     * @param amount Amount of tokens to deposit
     *
     * @dev
     * - Uses SafeERC20 to handle non-standard ERC20s
     * - Rejects fee-on-transfer tokens by enforcing exact receipt
     *
     * Requirements:
     * - Vault must not be paused
     * - token must not be zero address
     * - amount must be greater than zero
     * - Exact `amount` must be received
     */
    function depositToken(address token, uint256 amount) external whenNotPaused {
        if (amount == 0) {
            revert BankV2__ZeroAmount();
        }
        if (token == address(0)) {
            revert BankV2__InvalidToken();
        }

        IERC20 erc20 = IERC20(token);

        uint256 balanceBefore = erc20.balanceOf(address(this));
        SafeERC20.safeTransferFrom(erc20, msg.sender, address(this), amount);
        uint256 balanceAfter = erc20.balanceOf(address(this));

        uint256 received = balanceAfter - balanceBefore;
        if (received != amount) {
            revert BankV2__FeeOnTransferDetected();
        }

        balances[msg.sender][token] += amount;
        totalBalances[token] += amount;

        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @notice Withdraw previously deposited ERC20 tokens
     * @param token ERC20 token address to withdraw
     * @param amount Amount of tokens to withdraw
     *
     * @dev
     * - Protected by ReentrancyGuard
     * - State updates occur before external calls
     *
     * Requirements:
     * - Vault must not be paused
     * - amount must be greater than zero
     * - Caller must have sufficient balance
     */
    function withdrawToken(address token, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) {
            revert BankV2__ZeroAmount();
        }

        uint256 userBalance = balances[msg.sender][token];
        if (userBalance < amount) {
            revert BankV2__InsufficientFunds();
        }

        balances[msg.sender][token] = userBalance - amount;
        totalBalances[token] -= amount;

        SafeERC20.safeTransfer(IERC20(token), msg.sender, amount);

        emit Withdraw(msg.sender, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get a user's deposited balance for a token
     * @param user Address of the user
     * @param token ERC20 token address
     * @return Amount deposited by the user for the token
     */
    function balanceOf(address user, address token) external view returns (uint256) {
        return balances[user][token];
    }

    /**
     * @notice Get the total deposited balance for a token
     * @param token ERC20 token address
     * @return Total amount deposited across all users
     */
    function totalBalanceOf(address token) external view returns (uint256) {
        return totalBalances[token];
    }
}
