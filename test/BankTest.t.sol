// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Bank} from "../src/Bank.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ReentrancyAttacker} from "../test/ReentrancyAttacker.t.sol";

contract BankTest is Test {
    Bank bank;

    address owner = address(this);
    address user = address(0x1);

    function setUp() public {
        bank = new Bank();

        vm.deal(user, 10 ether);
    }

    // UNIT TESTS
    function testDepositIncreasesBalances() public {
        vm.prank(user);
        bank.deposit{value: 1 ether}();

        assertEq(bank.balanceOf(user), 1 ether);
        assertEq(address(bank).balance, 1 ether);
    }

    function testWithdrawDecreasesBalance() public {
        vm.prank(user);
        bank.deposit{value: 2 ether}();

        vm.prank(user);
        bank.withdraw(1 ether);

        assertEq(bank.balanceOf(user), 1 ether);
        assertEq(address(bank).balance, 1 ether);
    }

    function testUserCannotWithdrawMoreThanBalance() public {
        vm.prank(user);
        bank.deposit{value: 1 ether}();

        vm.prank(user);
        vm.expectRevert();
        bank.withdraw(2 ether);
    }

    function testPausingWorkCorrectly() public {
        bank.pause();

        vm.prank(user);
        vm.expectRevert();
        bank.deposit{value: 1 ether}();

        vm.prank(user);
        vm.expectRevert();
        bank.withdraw(1 ether);
    }

    // function testReentrancyAttackFails() public {
    //     ReentrancyAttacker attacker = new ReentrancyAttacker(bank);

    //     vm.deal(address(attacker), 1 ether);

    //     vm.expectRevert();
    //     attacker.attack{value: 1 ether}();
    // }

    function testForcedETHDoesNotAffectAccounting() public {
        vm.prank(user);
        bank.deposit{value: 1 ether}();

        ForceETH force = new ForceETH{value: 5 ether}();
        force.destroy(address(bank));

        // Accounting unchaned
        assertEq(bank.balanceOf(user), 1 ether);
        assertEq(address(bank).balance, 6 ether);
    }
}

contract ForceETH {
    constructor() payable {}

    function destroy(address target) external {
        selfdestruct(payable(target));
    }
}
