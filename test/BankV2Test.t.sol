// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BankV2} from "../src/BankV2.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract BankV2Test is Test {
    /*//////////////////////////////////////////////////////////////
                                TEST STATE
    //////////////////////////////////////////////////////////////*/
    BankV2 internal bank;
    ERC20Mock internal token;
    ERC20Mock internal token2;

    address internal owner;
    address internal user1;
    address internal user2;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy a standard, well-behaved ERC20
        token = new ERC20Mock();

        // Deploy BankV2
        vm.prank(owner);
        bank = new BankV2(owner);

        // Mint tokens to users
        token.mint(user1, 1_000 ether);
        token.mint(user2, 1_000 ether);

        // Approvals
        vm.prank(user1);
        token.approve(address(bank), type(uint256).max);

        vm.prank(user2);
        token.approve(address(bank), type(uint256).max);

        token2 = new ERC20Mock();
        token2.mint(user1, 1_000 ether);

        vm.prank(user1);
        token2.approve(address(bank), type(uint256).max);
    }

    function testDepositIncreasesBalances() public {
        uint256 amount = 100 ether;

        vm.prank(user1);
        bank.depositToken(address(token), amount);

        // User balance updated
        assertEq(bank.balanceOf(user1, address(token)), amount, "user balance incorrect");

        // Total balance updated
        assertEq(bank.totalBalanceOf(address(token)), amount, "total balance incorrect");

        // Bank actually holds the tokens
        assertEq(token.balanceOf(address(bank)), amount, "bank token balance incorrect");
    }

    function testWithdrawDecreasesBalances() public {
        uint256 depositAmount = 200 ether;
        uint256 withdrawAmount = 80 ether;

        // Deposit first
        vm.prank(user1);
        bank.depositToken(address(token), depositAmount);

        // Withdraw
        vm.prank(user1);
        bank.withdrawToken(address(token), withdrawAmount);

        // Remaining user balance
        assertEq(bank.balanceOf(user1, address(token)), depositAmount - withdrawAmount, "user balance not decreased");

        // Remaining total balance
        assertEq(bank.totalBalanceOf(address(token)), depositAmount - withdrawAmount, "total balance not decreased");

        // Tokens returned to user
        assertEq(token.balanceOf(user1), 1_000 ether - depositAmount + withdrawAmount, "user token balance incorrect");
    }

    function testCannotWithdrawMoreThanDeposited() public {
        uint256 depositAmount = 50 ether;

        vm.prank(user1);
        bank.depositToken(address(token), depositAmount);

        vm.prank(user1);
        vm.expectRevert(BankV2.BankV2__InsufficientFunds.selector);
        bank.withdrawToken(address(token), depositAmount + 1);
    }

    function testPerTokenAccountingIsolation() public {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 300 ether;

        vm.prank(user1);
        bank.depositToken(address(token), amount1);

        vm.prank(user1);
        bank.depositToken(address(token2), amount2);

        // Token 1 accounting
        assertEq(bank.balanceOf(user1, address(token)), amount1);
        assertEq(bank.totalBalanceOf(address(token)), amount1);

        // Token 2 accounting
        assertEq(bank.balanceOf(user1, address(token2)), amount2);
        assertEq(bank.totalBalanceOf(address(token2)), amount2);

        // Ensure isolation
        assertEq(bank.totalBalanceOf(address(token)), amount1);
        assertEq(bank.totalBalanceOf(address(token2)), amount2);
    }

    function testPauseBlocksDepositsAndWithdrawals() public {
        uint256 amount = 100 ether;

        // Owner pauses the bank
        vm.prank(owner);
        bank.pause();

        // Deposit should revert
        vm.prank(user1);
        vm.expectRevert(BankV2.BankV2__Paused.selector);
        bank.depositToken(address(token), amount);

        // Unpause
        vm.prank(owner);
        bank.unpause();

        // Deposit succeeds
        vm.prank(user1);
        bank.depositToken(address(token), amount);

        // Pause again
        vm.prank(owner);
        bank.pause();

        // Withdraw should revert
        vm.prank(user1);
        vm.expectRevert(BankV2.BankV2__Paused.selector);
        bank.withdrawToken(address(token), amount);
    }
}
