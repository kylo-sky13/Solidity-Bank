// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BankV2} from "../../src/BankV2.sol";

contract ReentrantWithdrawer {
    BankV2 public bank;
    address public token;
    bool internal attacked;

    constructor(address _bank, address _token) {
        bank = BankV2(_bank);
        token = _token;
    }

    function attack(uint256 amount) external {
        bank.withdrawToken(token, amount);
    }

    fallback() external {
        if (!attacked) {
            attacked = true;
            bank.withdrawToken(token, 1);
        }
    }
}
