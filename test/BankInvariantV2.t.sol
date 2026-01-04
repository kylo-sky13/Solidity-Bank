// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {BankV2} from "../../src/BankV2.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {BankV2Handler} from "test/BankV2Handler.sol";

contract BankV2InvariantTest is StdInvariant, Test {
    BankV2 public bank;
    ERC20Mock public token;
    BankV2Handler public handler;

    function setUp() public {
        bank = new BankV2(address(this));
        token = new ERC20Mock();

        handler = new BankV2Handler(bank, token);

        targetContract(address(handler));
    }

    function invariant_sumBalancesEqualsTotalDeposits() public view {
        uint256 sum;

        for (uint256 i = 0; i < handler.usersLength(); i++) {
            address user = handler.getUser(i);
            sum += bank.balanceOf(user, address(token));
        }

        assertEq(sum, bank.totalBalanceOf(address(token)));
    }

    function invariant_bankIsSolvent() public view {
        assertGe(token.balanceOf(address(bank)), bank.totalBalanceOf(address(token)));
    }

    function invariant_noAccountingChangeWhilePaused() public view {
        if (handler.wasPaused()) {
            assertEq(
                bank.totalBalanceOf(address(token)), handler.pausedTotalBalance(), "accounting changed while paused"
            );
        }
    }
}
