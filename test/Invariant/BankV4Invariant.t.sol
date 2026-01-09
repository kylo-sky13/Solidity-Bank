// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BankV4} from "../../src/BankV4.sol";
import {MockStrategy} from "../../src/strategy/MockStrategy.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IStrategy} from "../../src/BankV4.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {MockERC20} from "lib/openzeppelin-contracts/lib/forge-std/src/mocks/MockERC20.sol";

contract BankV4Handler is StdInvariant, Test {
    BankV4 public bank;
    MockStrategy public strategy;
    IERC20 public asset;

    address[] public users;

    constructor(BankV4 _bank, MockStrategy _strategy, IERC20 _asset) {
        bank = _bank;
        strategy = _strategy;
        asset = _asset;

        users.push(address(0x1));
        users.push(address(0x2));
        users.push(address(0x3));

        // One-time funding + approvals
        for (uint256 i = 0; i < users.length; i++) {
            deal(address(asset), users[i], 1_000 ether);

            vm.prank(users[i]);
            asset.approve(address(bank), type(uint256).max); // ensuring deposits never fail due to allowance
        }
    }

    /*//////////////////////////////////////////////////////////////
                            USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 userSeed, uint256 amount) public {
        address user = users[userSeed % users.length];
        amount = bound(amount, 1 ether, 100 ether);

        vm.prank(user);
        bank.deposit(amount, user);
    }

    function withdraw(uint256 userSeed, uint256 amount) public {
        // Random seed → deterministic user selection.
        address user = users[userSeed % users.length];
        uint256 max = bank.maxWithdraw(user);
        if (max == 0) return;

        amount = bound(amount, 1, max);

        vm.prank(user);
        bank.withdraw(amount, user, user);
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY ACTIONS
    //////////////////////////////////////////////////////////////*/

    function deploy(uint256 amount) public {
        uint256 idle = asset.balanceOf(address(bank));
        if (idle == 0) return;

        amount = bound(amount, 1, idle);
        bank.deployToStrategy(amount);
    }

    function gain(uint256 amount) public {
        uint256 managed = strategy.managedAssets();
        if (managed == 0) return;

        amount = bound(amount, 1, managed);
        strategy.simulateGain(amount);
    }

    function loss(uint256 amount) public {
        uint256 managed = strategy.managedAssets();
        if (managed == 0) return;

        amount = bound(amount, 1, managed);
        strategy.simulateLoss(amount);
    }

    function invariant_totalAssetsEqualsIdlePlusStrategy() public {
        uint256 idleAssets = IERC20(address(asset)).balanceOf(address(bank));
        uint256 strategyAssets = strategy.managedAssets();

        assertEq(bank.totalAssets(), idleAssets + strategyAssets);
    }

    function invariant_noShareInflation() public {
        assertLe(bank.totalSupply(), bank.totalAssets());
    }
}

