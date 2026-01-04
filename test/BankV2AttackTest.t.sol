// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BankV2} from "../src/BankV2.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {FeeOnTransferERC20} from "test/mocks/FeeOnTransferERC20.sol";
import {FalseReturnERC20} from "test/mocks/FalseReturnERC20.sol";
import {ERC777LikeERC20} from "test/mocks/ERC777LikeERC20.sol";
import {ERC777CallbackAttacker} from "test/ERC777CallbackAttacker.sol";
import {ReentrantWithdrawer} from "test/mocks/ReentrantWithdrawer .sol";

contract BankV2AttackTest is Test {
    address internal owner = address(0x1);
    address internal user1 = address(0x2);

    /*//////////////////////////////////////////////////////////////
                                FEE TOKEN
    //////////////////////////////////////////////////////////////*/

    function testFeeOnTransferDepositReverts() public {
        FeeOnTransferERC20 feeToken = new FeeOnTransferERC20();
        BankV2 feeBank = new BankV2(address(feeToken));

        feeToken.mint(user1, 100 ether);

        vm.startPrank(user1);
        feeToken.approve(address(feeBank), 100 ether);

        vm.expectRevert();
        feeBank.depositToken(user1, 100 ether);

        vm.stopPrank();
    }

    /*////////////////////////////////////////////////////////////
                         FALSE RETURN TOKEN
    //////////////////////////////////////////////////////////////*/

    function testERC20ReturningFalseIsRejected() public {
        FalseReturnERC20 badToken = new FalseReturnERC20();
        BankV2 badBank = new BankV2(address(badToken));

        badToken.mint(user1, 100 ether);

        vm.startPrank(user1);
        badToken.approve(address(badBank), 100 ether);

        vm.expectRevert();
        badBank.depositToken(user1, 100 ether);

        vm.stopPrank();
    }

    function testERC777StyleCallbackAttackFails() public {
        ERC777LikeERC20 token777 = new ERC777LikeERC20();
        BankV2 bank777 = new BankV2(owner);

        token777.mint(user1, 100 ether);

        ERC777CallbackAttacker attacker = new ERC777CallbackAttacker(address(bank777), address(token777));

        token777.setHook(address(attacker));

        vm.startPrank(user1);
        token777.approve(address(bank777), 100 ether);

        vm.expectRevert();
        bank777.depositToken(address(token777), 100 ether);

        vm.stopPrank();
    }

    function testReentrancyDuringWithdrawFails() public {
        ERC20Mock token = new ERC20Mock();
        BankV2 bank = new BankV2(owner);

        token.mint(address(this), 100 ether);
        token.approve(address(bank), 100 ether);

        bank.depositToken(address(token), 100 ether);

        ReentrantWithdrawer attacker = new ReentrantWithdrawer(address(bank), address(token));

        vm.expectRevert();
        attacker.attack(10 ether);
    }
}
