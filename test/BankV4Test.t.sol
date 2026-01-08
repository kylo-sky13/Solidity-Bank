// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BankV4} from "../src/BankV4.sol";
import {MockStrategy} from "../src/strategy/MockStrategy.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IStrategy} from "../src/BankV4.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";

/*//////////////////////////////////////////////////////////////
                          TEST ASSET
//////////////////////////////////////////////////////////////*/

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/*//////////////////////////////////////////////////////////////
                        BANK V4 TESTS
//////////////////////////////////////////////////////////////*/

contract BankV4Test is StdInvariant, Test {
    BankV4 internal bank;
    MockStrategy internal strategy;
    MockERC20 internal asset;

    address internal user1 = address(0x1);
    address internal user2 = address(0x2);

    function setUp() public {
        // Deploy mock ERC20 asset
        asset = new MockERC20();

        // Deploy strategy FIRST (vault not known yet)
        strategy = new MockStrategy(IERC20(address(asset)));

        // Deploy BankV4 vault
        bank = new BankV4(IERC20(address(asset)), IStrategy(address(strategy)), "BankV4 Share", "bV4");

        // Wire vault into strategy (one-time)
        strategy.setVault(address(bank));

        // Fund test user
        asset.mint(user1, 1_000 ether);

        // Approvals
        vm.prank(user1);
        asset.approve(address(bank), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositMintsShares() public {
        vm.prank(user1);
        uint256 shares = bank.deposit(100 ether, user1);

        assertEq(shares, 100 ether);
        assertEq(bank.balanceOf(user1), 100 ether);
        assertEq(bank.totalAssets(), 100 ether);
    }

    function testDepositDoesNotDeployToStrategy() public {
        vm.prank(user1);
        bank.deposit(200 ether, user1);

        assertEq(strategy.managedAssets(), 0);
        assertEq(IERC20(address(asset)).balanceOf(address(bank)), 200 ether);
        assertEq(bank.totalAssets(), 200 ether);
    }

    function testManualDeployToStrategy() public {
        vm.prank(user1);
        bank.deposit(300 ether, user1);

        bank.deployToStrategy(200 ether);

        assertEq(strategy.managedAssets(), 200 ether);
        assertEq(IERC20(address(asset)).balanceOf(address(bank)), 100 ether);
        assertEq(bank.totalAssets(), 300 ether);
    }

    function testWithdrawUsesIdleAssetsFirst() public {
        vm.prank(user1);
        bank.deposit(300 ether, user1);

        bank.deployToStrategy(200 ether);

        vm.prank(user1);
        bank.withdraw(50 ether, user1, user1);

        assertEq(strategy.managedAssets(), 200 ether);
        assertEq(IERC20(address(asset)).balanceOf(address(bank)), 50 ether);
        assertEq(bank.balanceOf(user1), 250 ether);
    }

    function testWithdrawUnwindsStrategy() public {
        vm.prank(user1);
        bank.deposit(300 ether, user1);

        bank.deployToStrategy(250 ether);

        vm.prank(user1);
        bank.withdraw(100 ether, user1, user1);

        assertEq(strategy.managedAssets(), 200 ether);
        assertEq(IERC20(address(asset)).balanceOf(address(bank)), 0);
        assertEq(bank.balanceOf(user1), 200 ether);
    }

    function testLossReducesPPS() public {
        vm.prank(user1);
        bank.deposit(200 ether, user1);

        bank.deployToStrategy(200 ether);
        strategy.simulateLoss(50 ether);

        uint256 assetsAfterLoss = bank.previewRedeem(bank.balanceOf(user1));
        assertEq(assetsAfterLoss, 150 ether);
    }

    function testTwoUsersLossSocialization() public {
        asset.mint(user2, 200 ether);
        vm.prank(user2);
        asset.approve(address(bank), type(uint256).max);

        vm.prank(user1);
        bank.deposit(100 ether, user1);

        vm.prank(user2);
        bank.deposit(100 ether, user2);

        bank.deployToStrategy(200 ether);
        strategy.simulateLoss(40 ether);

        uint256 user1Assets = bank.previewRedeem(bank.balanceOf(user1));
        uint256 user2Assets = bank.previewRedeem(bank.balanceOf(user2));

        assertEq(user1Assets, 80 ether);
        assertEq(user2Assets, 80 ether);
    }

    function testDeployToStrategyMovesAssets() public {
        vm.prank(user1);
        bank.deposit(200 ether, user1);

        bank.deployToStrategy(150 ether);

        assertEq(asset.balanceOf(address(bank)), 50 ether);
        assertEq(strategy.totalAssets(), 150 ether);
        assertEq(bank.totalAssets(), 200 ether);
    }

    function testWithdrawPullsFromStrategyIfNeeded() public {
        vm.prank(user1);
        bank.deposit(300 ether, user1);

        bank.deployToStrategy(250 ether);

        vm.prank(user1);
        bank.withdraw(200 ether, user1, user1);

        assertEq(asset.balanceOf(user1), 900 ether);
        assertEq(bank.totalAssets(), 100 ether);
    }
}
