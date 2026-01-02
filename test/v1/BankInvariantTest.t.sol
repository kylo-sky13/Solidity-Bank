// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Bank} from "../../src/Bank.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";

contract BankInvariantTest is StdInvariant, Test {
    Bank bank;
    address user = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        bank = new Bank();
        vm.deal(user, 100 ether);
        vm.deal(user2, 200 ether);
    }

    function invariant__Solvency() public {
        assert(address(bank).balance >= bank.getTotalDeposits());
    }

    function invariant__BalanceConservation() public {
        uint256 sum = bank.balanceOf(user) + bank.balanceOf(user2);

        assertEq(sum, bank.getTotalDeposits());
    }
}
