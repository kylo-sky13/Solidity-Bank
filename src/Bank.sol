// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract Bank is ReentrancyGuard {
    // STATE VARIABLES
    uint256 internal totalDeposits; // ETH deposited by all users
    bool internal paused; // Emergency stop flag
    address internal owner; // Pause Controller

    // CONSTRUCTORS
    constructor() {
        owner = msg.sender;
    }

    // MAPPINGS
    mapping(address => uint256) internal balances; // Sum of all user balances

    // ERRORS
    error Bank__ZeroValueDeposits();
    error Bank__ContractIsPaused();
    error Bank__UserHasNoETH();
    error Bank__NoZeroValueWithdrawls();
    error Bank__InsuffientBalance();
    error Bank__ETHTransferFailed();
    error Bank__NotOwner();
    error Bank__ContractIsNOTPaused();

    // EVENTS
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event Paused(address indexed caller);
    event Unpaused(address indexed caller);

    function deposit() external payable {
        // C
        if (paused) {
            revert Bank__ContractIsPaused();
        }
        if (msg.value == 0) {
            revert Bank__ZeroValueDeposits();
        }

        // E
        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;

        // I
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 withdrawAmount) external nonReentrant {
        uint256 userBalance = balances[msg.sender];

        //C
        if (paused) {
            revert Bank__ContractIsPaused();
        }
        if (withdrawAmount == 0) {
            revert Bank__NoZeroValueWithdrawls();
        }
        if (withdrawAmount > userBalance) {
            revert Bank__InsuffientBalance();
        }

        //E
        balances[msg.sender] = userBalance - withdrawAmount;
        totalDeposits -= withdrawAmount;

        // I
        (bool success,) = msg.sender.call{value: withdrawAmount}("");
        if (!success) {
            revert Bank__ETHTransferFailed();
        }
        emit Withdrawal(msg.sender, withdrawAmount);
    }

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    function pause() external {
        if (msg.sender != owner) {
            revert Bank__NotOwner();
        }
        if (paused) {
            revert Bank__ContractIsPaused();
        }

        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external {
        if (msg.sender != owner) {
            revert Bank__NotOwner();
        }
        if (!paused) {
            revert Bank__ContractIsNOTPaused();
        }

        paused = false;
        emit Unpaused(msg.sender);
    }

    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }
}
