// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BankV2} from "../../src/BankV2.sol";

contract ERC777CallbackAttacker {
    BankV2 public bank;
    address public token;

    constructor(address _bank, address _token) {
        bank = BankV2(_bank);
        token = _token;
    }

    function tokensReceived() external {
        // Attempt to reenter deposit or withdraw
        bank.withdrawToken(token, 1);
    }
}
