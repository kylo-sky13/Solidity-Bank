// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BankV2} from "src/BankV2.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Test} from "forge-std/Test.sol";

contract BankV2Handler is Test {
    BankV2 public bank;
    ERC20Mock public token;

    address[] public users;

    bool public wasPaused;
    uint256 public pausedTotalBalance;

    constructor(BankV2 _bank, ERC20Mock _token) {
        bank = _bank;
        token = _token;

        users.push(address(0xA1));
        users.push(address(0xB2));
        users.push(address(0xC3));

        for (uint256 i = 0; i < users.length; i++) {
            token.mint(users[i], 1_000 ether);
        }
    }

    function deposit(uint256 userIndex, uint256 amount) external {
        address user = users[userIndex % users.length];
        amount = bound(amount, 1, 100 ether);

        vm.startPrank(user);
        token.approve(address(bank), amount);
        bank.depositToken(address(token), amount);
        vm.stopPrank();
    }

    function withdraw(uint256 userIndex, uint256 amount) external {
        address user = users[userIndex % users.length];

        uint256 balance = bank.balanceOf(user, address(token));
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.startPrank(user);
        bank.withdrawToken(address(token), amount);
        vm.stopPrank();
    }

    function usersLength() external view returns (uint256) {
        return users.length;
    }

    function getUser(uint256 index) external view returns (address) {
        return users[index];
    }

    function pause() external {
        if (!bank.paused()) {
            bank.pause();
            wasPaused = true;
            pausedTotalBalance = bank.totalBalanceOf(address(token));
        }
    }

    function unpause() external {
        if (bank.paused()) {
            bank.unpause();
            wasPaused = false;
        }
    }
}
