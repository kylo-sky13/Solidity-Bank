// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";
import {BankV3} from "../src/BankV3.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

/// @title BankV3Test
/// @notice Comprehensive test suite for the BankV3 ERC4626 vault
/// @dev Verifies ERC4626 compliance, rounding behavior, donation safety,
///      preview/execution parity, pausing semantics, and solvency invariants
contract BankV3Test is Test {
    BankV3 bank;
    ERC20Mock asset;

    address user1 = address(0x1);
    address user2 = address(0x2);

    /// @notice Sets up a fresh BankV3 vault and mock ERC20 asset before each test
    /// @dev Mints assets to test users and grants unlimited approval to the vault
    function setUp() public {
        asset = new ERC20Mock();
        bank = new BankV3(asset, "Bank Share", "BSH");

        asset.mint(user1, 1_000 ether);
        asset.mint(user2, 1_000 ether);

        vm.prank(user1);
        asset.approve(address(bank), type(uint256).max);

        vm.prank(user2);
        asset.approve(address(bank), type(uint256).max);
    }

    /// @notice Verifies first deposit mints shares 1:1 with assets
    /// @dev Required ERC4626 zero-supply behavior
    function test_FirstDeposit_IsOneToOne() public {
        vm.prank(user1);
        uint256 shares = bank.deposit(100 ether, user1);

        assertEq(shares, 100 ether);
        assertEq(bank.totalSupply(), 100 ether);
        assertEq(bank.totalAssets(), 100 ether);
        assertEq(bank.balanceOf(user1), 100 ether);
    }

    /// @notice Ensures deposits after initialization mint proportional shares
    function test_Deposit_IsProportional() public {
        vm.prank(user1);
        bank.deposit(100 ether, user1);

        vm.prank(user2);
        uint256 shares = bank.deposit(50 ether, user2);

        assertEq(shares, 50 ether);
        assertEq(bank.totalSupply(), 150 ether);
        assertEq(bank.totalAssets(), 150 ether);
    }

    /// @notice Forced asset donations must increase share value
    /// @dev Donations must not mint new shares
    function test_Donation_IncreasesShareValue() public {
        vm.prank(user1);
        bank.deposit(100 ether, user1);

        asset.mint(address(bank), 100 ether);

        assertEq(bank.totalAssets(), 200 ether);
        assertEq(bank.convertToAssets(100 ether), 200 ether);
    }

    /// @notice Withdraw must burn shares rounded UP
    /// @dev Conservative rounding prevents withdrawing excess value
    function test_Withdraw_BurnsRoundedUpShares() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        vm.prank(user1);
        uint256 burned = bank.withdraw(1 ether, user1, user1);

        assertEq(burned, 1 ether);
        assertEq(bank.balanceOf(user1), 2 ether);
    }

    /// @notice Redeem must return assets rounded DOWN
    /// @dev Ensures rounding always favors the vault
    function test_Redeem_RoundsDownAssets() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        asset.mint(address(bank), 1 ether);

        vm.prank(user1);
        uint256 assets = bank.redeem(1 ether, user1, user1);

        assertEq(assets, 1333333333333333333);
    }

    /// @notice previewDeposit must match actual deposit execution
    function test_PreviewDeposit_MatchesDepositMath() public {
        vm.prank(user1);
        bank.deposit(100 ether, user1);

        uint256 preview = bank.previewDeposit(50 ether);

        vm.prank(user2);
        uint256 actual = bank.deposit(50 ether, user2);

        assertEq(preview, actual);
    }

    /// @notice Pausing the vault must block all state-changing actions
    function test_Pause_DisablesStateChangingFunctions() public {
        bank.pause();

        vm.expectRevert();
        vm.prank(user1);
        bank.deposit(1 ether, user1);

        vm.expectRevert();
        vm.prank(user1);
        bank.withdraw(1 ether, user1, user1);
    }

    /// @notice maxRedeem must equal the caller’s share balance
    function test_MaxRedeem_EqualsBalance() public {
        vm.prank(user1);
        bank.deposit(10 ether, user1);

        assertEq(bank.maxRedeem(user1), 10 ether);
    }

    /// @notice Withdraw share burn must round UP when PPS > 1
    function test_Withdraw_RoundsUpShares() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        asset.mint(address(bank), 1 ether);

        vm.prank(user1);
        uint256 sharesBurned = bank.withdraw(1 ether, user1, user1);

        assertEq(sharesBurned, 0.75 ether);
    }

    /// @notice Mint must consume assets rounded UP
    function test_Mint_RoundsUpAssets() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        asset.mint(address(bank), 1 ether);

        vm.prank(user2);
        uint256 assetsUsed = bank.mint(1 ether, user2);

        assertEq(assetsUsed, 1333333333333333334);
    }

    /// @notice Deposit must mint shares rounded DOWN
    function test_Deposit_RoundsDownShares() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        asset.mint(address(bank), 1 ether);

        uint256 preview = bank.previewDeposit(1 ether);
        assertEq(preview, 0.75 ether);

        vm.prank(user2);
        uint256 minted = bank.deposit(1 ether, user2);

        assertEq(minted, preview);
    }

    /// @notice previewRedeem must exactly match redeem
    function test_PreviewRedeem_Parity() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        asset.mint(address(bank), 1 ether);

        uint256 previewAssets = bank.previewRedeem(1 ether);

        vm.prank(user1);
        uint256 actualAssets = bank.redeem(1 ether, user1, user1);

        assertEq(actualAssets, previewAssets);
    }

    /// @notice previewWithdraw must exactly match withdraw
    function test_PreviewWithdraw_Parity() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        asset.mint(address(bank), 1 ether);

        uint256 previewShares = bank.previewWithdraw(1 ether);

        vm.prank(user1);
        uint256 actualShares = bank.withdraw(1 ether, user1, user1);

        assertEq(actualShares, previewShares);
    }

    /// @notice previewDeposit must handle zero-supply case correctly
    function test_PreviewDeposit_ZeroSupply() public {
        assertEq(bank.previewDeposit(10 ether), 10 ether);
    }

    /// @notice Preview functions must not mutate contract state
    function test_PreviewFunctions_DoNotChangeState() public {
        uint256 supplyBefore = bank.totalSupply();
        uint256 assetsBefore = bank.totalAssets();

        bank.previewDeposit(1 ether);
        bank.previewWithdraw(1 ether);
        bank.previewMint(1 ether);
        bank.previewRedeem(1 ether);

        assertEq(bank.totalSupply(), supplyBefore);
        assertEq(bank.totalAssets(), assetsBefore);
    }

    /// @notice Donations must not mint shares implicitly
    function test_Donation_DoesNotMintShares() public {
        vm.prank(user1);
        bank.deposit(5 ether, user1);

        uint256 supplyBefore = bank.totalSupply();

        asset.mint(address(bank), 5 ether);

        uint256 supplyAfter = bank.totalSupply();

        assertEq(supplyAfter, supplyBefore);
    }

    /// @notice Users must not redeem more shares than they own
    function test_CannotRedeemMoreThanBalance() public {
        vm.prank(user1);
        bank.deposit(2 ether, user1);

        uint256 excessShares = bank.balanceOf(user1) + 1;

        vm.prank(user1);
        vm.expectRevert();
        bank.redeem(excessShares, user1, user1);
    }

    /// @notice maxWithdraw must equal asset value of user shares
    function test_MaxWithdraw_EqualsAssetsValue() public {
        vm.prank(user1);
        bank.deposit(3 ether, user1);

        asset.mint(address(bank), 1 ether);

        uint256 expected = bank.convertToAssets(bank.balanceOf(user1));
        assertEq(bank.maxWithdraw(user1), expected);
    }

    /// @notice Withdrawing maxWithdraw must leave zero shares
    function test_WithdrawAll_LeavesZeroShares() public {
        vm.prank(user1);
        bank.deposit(5 ether, user1);

        uint256 maxAssets = bank.maxWithdraw(user1);

        vm.prank(user1);
        bank.withdraw(maxAssets, user1, user1);

        assertEq(bank.balanceOf(user1), 0);
    }

    /// @notice Redeeming maxRedeem must leave zero shares
    function test_RedeemAll_LeavesZeroShares() public {
        vm.prank(user1);
        bank.deposit(5 ether, user1);

        uint256 maxShares = bank.maxRedeem(user1);

        vm.prank(user1);
        bank.redeem(maxShares, user1, user1);

        assertEq(bank.balanceOf(user1), 0);
    }

    /// @notice Deposits are intentionally unbounded
    function test_MaxDeposit_Unbounded() public {
        assertEq(bank.maxDeposit(user1), type(uint256).max);
    }

    /// @notice Mints are intentionally unbounded
    function test_MaxMint_Unbounded() public {
        assertEq(bank.maxMint(user1), type(uint256).max);
    }

    /// @notice Donations must benefit existing shareholders over new entrants
    function test_Donation_BenefitsExistingHolders() public {
        vm.prank(user1);
        bank.deposit(10 ether, user1);

        asset.mint(address(bank), 10 ether);

        vm.prank(user2);
        bank.deposit(10 ether, user2);

        assertGt(bank.convertToAssets(bank.balanceOf(user1)), 10 ether);
    }

    /// @notice Invariant: vault assets must always cover all share claims
    /// @dev Expressed as totalAssets >= convertToAssets(totalSupply)
    function invariant_TotalAssetsGTEUserClaims() public {
        uint256 supply = bank.totalSupply();
        if (supply == 0) return;

        assertGe(bank.totalAssets(), bank.convertToAssets(supply));
    }
}
