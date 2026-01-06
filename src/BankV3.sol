// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BankV3
 * @author kylo_sky
 *
 * @notice
 * BankV3 is a production-grade, single-asset ERC4626 vault implementing
 * share-based accounting with no yield, no strategies, and no governance.
 *
 * This contract represents Version 3 of the Solidity Bank project:
 *  - V1: ETH-only vault
 *  - V2: Single-asset ERC20 vault without shares
 *  - V3: ERC4626-compliant, share-based vault
 *
 * BankV3 standardizes vault behavior using ERC4626 while preserving
 * strict safety, solvency, and rounding guarantees.
 *
 * -------------------------------------------------------------------------
 * CORE DESIGN PRINCIPLES
 * -------------------------------------------------------------------------
 *
 * 1. ERC4626 is the sole source of accounting truth
 *    - User balances are represented exclusively by ERC20 shares
 *    - Asset balances are derived proportionally from totalAssets / totalSupply
 *    - No parallel accounting, mappings, or shadow balances exist
 *
 * 2. Deterministic, vault-favoring math
 *    - All conversions are proportional
 *    - Rounding always favors the vault, never the user
 *    - Rounding dust remains in the vault and benefits all shareholders
 *
 * 3. Donation- and fee-token-safe
 *    - Deposits use balance-delta accounting
 *    - Forced token transfers are treated as donations
 *    - Donations increase share value but never mint shares
 *
 * 4. No hidden economics
 *    - No yield, interest, or rewards
 *    - No performance or management fees
 *    - No strategy deployment
 *
 * -------------------------------------------------------------------------
 * ACCOUNTING MODEL
 * -------------------------------------------------------------------------
 *
 * Let:
 *   S = totalSupply()  (total shares)
 *   T = totalAssets()  (underlying token balance)
 *
 * User asset ownership is derived as:
 *   userAssets = shares * T / S
 *
 * Initial conditions (zero-supply case):
 *   - On first deposit: shares == assets
 *   - Initial exchange rate is exactly 1:1
 *
 * Conversion rules:
 *   - convertToShares: rounds DOWN
 *   - convertToAssets: rounds DOWN
 *   - withdraw burns shares rounded UP
 *   - redeem pays assets rounded DOWN
 *
 * -------------------------------------------------------------------------
 * SECURITY & SAFETY GUARANTEES
 * -------------------------------------------------------------------------
 *
 * - Solvency:
 *     totalAssets() == IERC20(asset).balanceOf(address(this))
 *
 * - Conservation:
 *     Shares minted <-> assets received
 *     Shares burned <-> assets sent
 *
 * - Reentrancy safety:
 *     - All state changes occur before external token transfers
 *     - Withdraw and redeem are protected via CEI and nonReentrant
 *
 * - Pause semantics:
 *     - deposit, mint, withdraw, redeem revert when paused
 *     - View and preview functions remain callable
 *
 * -------------------------------------------------------------------------
 * ERC4626 PREVIEW SEMANTICS
 * -------------------------------------------------------------------------
 *
 * Preview functions mirror execution math exactly, excluding side effects.
 * They assume ideal ERC20 behavior and may overestimate results for
 * fee-on-transfer tokens. This is intentional and documented.
 *
 * Invariant:
 *   previewX(...) == X(...) math ignoring transfers
 *
 * -------------------------------------------------------------------------
 * EXPLICIT NON-GOALS
 * -------------------------------------------------------------------------
 *
 * BankV3 does NOT:
 *   - Generate yield or interest
 *   - Invest assets into external strategies
 *   - Support multiple assets per deployment
 *   - Support rebasing or ERC777 tokens
 *   - Implement upgrades or migrations
 *   - Include governance or admin-controlled economics
 *
 * Unsupported tokens must be considered unsafe unless explicitly audited.
 *
 * -------------------------------------------------------------------------
 * REQUIRED ASSET ASSUMPTIONS
 * -------------------------------------------------------------------------
 * /**
 * @notice ERC4626-compliant single-asset vault
 *
 * @dev ASSET REQUIREMENTS:
 * - MUST be a non-rebasing ERC20
 * - MUST NOT be ERC777
 * - MUST NOT implement transfer hooks or callbacks
 * - balanceOf(address) MUST only change via transfers
 *
 * Violating any of the above breaks vault accounting invariants.
 *
 * -------------------------------------------------------------------------
 * AUDIT NOTES
 * -------------------------------------------------------------------------
 *
 * - This contract is intended to be simple, transparent, and audit-friendly
 * - All critical math is explicit and documented
 * - There are no hidden invariants beyond those stated here
 *
 * BankV3 is designed to be a stable ERC4626 primitive upon which
 * more complex economic behavior may be safely built in future versions.
 */

contract BankV3 is ERC4626, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BankV3_ZeroAssets();
    error BankV3_ZeroShares();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC4626(asset_) {
        // IMPORTANT:
        // - ERC4626 (OpenZeppelin) overrides decimals()
        // - Share decimals == asset decimals
        // - We intentionally do NOT override decimals()
    }

    /*//////////////////////////////////////////////////////////////
                        ASSET ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total underlying assets held by the vault
     * @dev Critical invariant:
     *      totalAssets() MUST equal the actual token balance.
     *      Forced transfers are treated as donations.
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSING CONTROLS
    //////////////////////////////////////////////////////////////*/

    function pause() external {
        _pause();
    }

    function unpause() external {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 CONVERSION MATH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Converts assets to shares using current vault state
     * @dev Rounds DOWN in all cases.
     *      If totalSupply == 0, shares == assets (1:1 bootstrap).
     */
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        if (assets == 0) return 0;

        uint256 supply = totalSupply();
        uint256 totalAssets_ = totalAssets();

        // Zero-supply case: first depositor
        if (supply == 0) {
            return assets;
        }

        // s = a * S / A   (rounding down)
        return (assets * supply) / totalAssets_;
    }

    /**
     * @notice Converts shares to assets using current vault state
     * @dev Rounds DOWN in all cases.
     */
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        if (shares == 0) return 0;

        uint256 supply = totalSupply();
        uint256 totalAssets_ = totalAssets();

        // If no shares exist, no assets are claimable
        if (supply == 0) {
            return 0;
        }

        // a = s * A / S   (rounding down)
        return (shares * totalAssets_) / supply;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit exact assets and receive shares
     * @dev Shares are rounded DOWN.
     *      Uses balance-delta accounting for safety.
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert BankV3_ZeroAssets();

        uint256 supply = totalSupply();
        uint256 totalAssetsBefore = totalAssets();

        // Pull assets in
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // Measure actual assets received (fee-safe)
        uint256 totalAssetsAfter = totalAssets();
        // Safe underflow: totalAssetsAfter >= totalAssetsBefore after transfer
        uint256 received = totalAssetsAfter - totalAssetsBefore;

        if (received == 0) {
            revert BankV3_ZeroAssets();
        }

        // Convert received assets to shares
        if (supply == 0) {
            shares = received;
        } else {
            shares = (received * supply) / totalAssetsBefore;
        }

        if (shares == 0) revert BankV3_ZeroShares();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, received, shares);
    }

    /**
     * @notice Withdraw an exact amount of underlying assets from the vault.
     *
     * @dev ERC4626 exit where the caller specifies `assets` and the vault
     *      computes the number of shares to burn.
     *
     *      Share burn calculation:
     *          shares = ceil(assets * totalSupply / totalAssets)
     *
     *      Rounding is performed UP to ensure the vault is never underpaid.
     *      This prevents:
     *        - Free asset extraction via rounding
     *        - Donation-based share price manipulation
     *        - Share inflation attacks
     *
     *      Accounting is based on pre-withdraw state:
     *        - totalSupply and totalAssets are read once at function entry
     *        - Shares are burned BEFORE assets are transferred
     *
     *      This function is reentrancy-safe:
     *        - All state changes (burn) occur before the external token transfer
     *
     * @param assets   Exact amount of underlying assets to withdraw
     * @param receiver Address receiving the withdrawn assets
     * @param owner    Address whose shares are burned
     *
     * @return shares  Number of shares burned (rounded up)
     */

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert BankV3_ZeroAssets();

        uint256 supply = totalSupply();
        uint256 totalAssetsBefore = totalAssets();

        // Compute shares to burn (ROUND UP)
        shares = (assets * supply + totalAssetsBefore - 1) / totalAssetsBefore;
        if (shares == 0) revert BankV3_ZeroShares();

        // Handle allowance if caller is not owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Burn shares FIRST (effects)
        _burn(owner, shares);

        // Transfer assets LAST (interaction)
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Redeem an exact number of vault shares for underlying assets.
     *
     * @dev ERC4626 exit where the caller specifies `shares` and receives
     *      the proportional amount of underlying assets.
     *
     *      Asset amount calculation:
     *          assets = floor(shares * totalAssets / totalSupply)
     *
     *      Rounding is performed DOWN to ensure the vault never overpays.
     *      Any rounding dust remains in the vault and benefits
     *      remaining shareholders proportionally.
     *
     *      Accounting is based on pre-redeem state:
     *        - totalSupply and totalAssets are read once at function entry
     *        - Shares are burned BEFORE assets are transferred
     *
     *      This function is reentrancy-safe:
     *        - Vault state is finalized prior to the external token transfer
     *
     * @param shares   Exact number of shares to redeem
     * @param receiver Address receiving the underlying assets
     * @param owner    Address whose shares are burned
     *
     * @return assets  Amount of underlying assets returned (rounded down)
     */

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert BankV3_ZeroShares();

        uint256 supply = totalSupply();
        uint256 totalAssetsBefore = totalAssets();

        // Convert shares to assets (ROUND DOWN)
        assets = (shares * totalAssetsBefore) / supply;
        if (assets == 0) revert BankV3_ZeroAssets();

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Burn shares FIRST
        _burn(owner, shares);

        // Transfer assets LAST
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                          PREVIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Preview the number of shares that would be minted for a given asset deposit.
     *
     * @dev This function mirrors the share calculation performed in `deposit`,
     *      excluding any token transfers or state changes.
     *
     *      Calculation:
     *        - If totalSupply == 0:
     *            shares = assets
     *        - Otherwise:
     *            shares = floor(assets * totalSupply / totalAssets)
     *
     *      Rounding is performed DOWN to favor the vault.
     *      Any rounding dust remains in the vault and benefits existing shareholders.
     *
     *      This preview assumes ideal ERC20 behavior (no transfer fees or burns).
     *      For fee-on-transfer tokens, actual shares minted during `deposit`
     *      MAY be less than this preview.
     *
     * @param assets Amount of underlying assets to deposit
     *
     * @return shares Number of shares that would be minted
     */

    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets;
        }

        uint256 totalAssets_ = totalAssets();

        // ROUND DOWN
        shares = (assets * supply) / totalAssets_;
    }

    /**
     * @notice Preview the amount of assets required to mint a given number of shares.
     *
     * @dev This function mirrors the asset calculation performed in `mint`,
     *      excluding any token transfers or state changes.
     *
     *      Calculation:
     *        - If totalSupply == 0:
     *            assets = shares
     *        - Otherwise:
     *            assets = ceil(shares * totalAssets / totalSupply)
     *
     *      Rounding is performed UP to ensure the vault is never underpaid.
     *      This prevents minting shares for fewer assets than their
     *      proportional value.
     *
     *      This preview assumes ideal ERC20 behavior and does not account for
     *      potential transfer fees that may apply during execution.
     *
     * @param shares Number of shares to mint
     *
     * @return assets Amount of assets required to mint the shares
     */

    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }

        uint256 totalAssets_ = totalAssets();

        // ROUND UP
        assets = (shares * totalAssets_ + supply - 1) / supply;
    }

    /**
     * @notice Preview the number of shares that would be burned to withdraw a given
     *         amount of underlying assets.
     *
     * @dev This function mirrors the share burn calculation performed in `withdraw`,
     *      excluding any token transfers or state changes.
     *
     *      Calculation:
     *        shares = ceil(assets * totalSupply / totalAssets)
     *
     *      Rounding is performed UP to ensure the vault is never underpaid.
     *      This prevents:
     *        - Free asset extraction via rounding
     *        - Donation-based share price manipulation
     *        - Share inflation attacks
     *
     *      The returned value represents the minimum number of shares that
     *      must be burned to receive the requested assets.
     *
     * @param assets Amount of underlying assets to withdraw
     *
     * @return shares Number of shares that would be burned
     */

    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            // Zero-supply: 1:1
            return assets;
        }

        uint256 totalAssets_ = totalAssets();

        // ROUND UP
        shares = (assets * supply + totalAssets_ - 1) / totalAssets_;
    }

    /**
     * @notice Preview the amount of underlying assets that would be received by
     *         redeeming a given number of shares.
     *
     * @dev This function mirrors the asset calculation performed in `redeem`,
     *      excluding any token transfers or state changes.
     *
     *      Calculation:
     *        assets = floor(shares * totalAssets / totalSupply)
     *
     *      Rounding is performed DOWN to ensure the vault never overpays assets.
     *      Any rounding dust remains in the vault and benefits remaining
     *      shareholders proportionally.
     *
     * @param shares Number of shares to redeem
     *
     * @return assets Amount of underlying assets that would be received
     */

    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }

        uint256 totalAssets_ = totalAssets();

        // ROUND DOWN
        assets = (shares * totalAssets_) / supply;
    }

    /**
     * @notice Maximum amount of underlying assets that can be deposited for `receiver`.
     *
     * @dev Since the vault does not impose deposit caps and does not deploy assets
     *      into external strategies, deposits are only restricted by the paused state.
     *
     *      When paused, deposits are fully disabled and this function returns 0.
     *      When unpaused, this function returns the maximum uint256 value, signaling
     *      that deposits are unrestricted.
     *
     * @param receiver Address that would receive the minted shares
     *
     * @return maxAssets Maximum amount of assets that can be deposited
     */

    /*//////////////////////////////////////////////////////////////
                    MAXIMUM DEPOSIT/MINT/WITHDRAW/REEDEEM
    //////////////////////////////////////////////////////////////*/
    function maxDeposit(address receiver) public view override returns (uint256 maxAssets) {
        receiver; // silence unused variable warning

        if (paused()) return 0;
        return type(uint256).max;
    }

    /**
     * @notice Maximum number of vault shares that can be minted for `receiver`.
     *
     * @dev Since the vault does not impose mint caps and does not restrict share
     *      creation beyond the paused state, minting is unrestricted when unpaused.
     *
     *      When paused, minting is fully disabled and this function returns 0.
     *      When unpaused, this function returns the maximum uint256 value.
     *
     *      Note: Actual mint execution may still be constrained by the caller's
     *      asset balance and allowance.
     *
     * @param receiver Address that would receive the minted shares
     *
     * @return maxShares Maximum number of shares that can be minted
     */
    function maxMint(address receiver) public view override returns (uint256 maxShares) {
        receiver; // silence unused variable warning

        if (paused()) return 0;
        return type(uint256).max;
    }

    /**
     * @notice Maximum amount of underlying assets that can be withdrawn by `owner`.
     *
     * @dev The maximum withdrawable assets are derived from the owner's share balance
     *      and the current vault exchange rate.
     *
     *      Calculation mirrors `previewRedeem(balanceOf(owner))`:
     *        assets = floor(shares * totalAssets / totalSupply)
     *
     *      When the vault is paused, withdrawals are disabled and this function
     *      returns 0.
     *
     * @param owner Address whose assets would be withdrawn
     *
     * @return maxAssets Maximum amount of assets withdrawable
     */
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        if (paused()) return 0;

        uint256 shares = balanceOf(owner);
        if (shares == 0) return 0;

        uint256 supply = totalSupply();
        uint256 totalAssets_ = totalAssets();

        // Start with floor conversion
        maxAssets = (shares * totalAssets_) / supply;

        // Adjust downward if withdraw(maxAssets) would burn > shares
        uint256 sharesRequired = (maxAssets * supply + totalAssets_ - 1) / totalAssets_; // ceil

        if (sharesRequired > shares) {
            maxAssets -= 1;
        }
    }

    /**
     * @notice Maximum number of vault shares that can be redeemed by `owner`.
     *
     * @dev The maximum redeemable shares are equal to the owner's share balance.
     *      No additional constraints are applied, as the vault always holds
     *      sufficient assets to honor proportional redemptions.
     *
     *      When the vault is paused, redemptions are disabled and this function
     *      returns 0.
     *
     * @param owner Address whose shares would be redeemed
     *
     * @return maxShares Maximum number of shares redeemable
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        if (paused()) return 0;
        return balanceOf(owner);
    }
}
