# Solidity Bank — BankV3

A **production-grade, security-first ERC4626 vault** built as an educational and portfolio project.

BankV3 represents the third iteration of the Solidity Bank series, evolving from simple balance-based accounting into a **share-based financial primitive** that strictly follows ERC4626 semantics.

This repository prioritizes **correctness, invariants, and explicit threat modeling over features**.

---

## Project Overview

**BankV3** is a:

* ✅ Single-asset-per-deployment ERC4626 vault
* ✅ Share-based accounting model
* ✅ Donation-safe and fee-on-transfer aware
* ✅ Deterministic, vault-favoring rounding
* ❌ No yield, no strategies, no fees
* ❌ No governance, no upgrades

It is designed to be **auditable, minimal, and mathematically correct**.

---

## Version History

| Version | Description                            |
| ------- | -------------------------------------- |
| **V1**  | ETH-only vault with balance accounting |
| **V2**  | ERC20 single-asset vault (no shares)   |
| **V3**  | ERC4626-compliant share-based vault    |

Each version is **frozen and tagged** once complete.

---

## Core Design Principles

### 1. ERC4626 Is the Sole Source of Truth

* User ownership is represented exclusively via ERC20 shares
* No parallel balance mappings
* All asset ownership is derived proportionally

```
userAssets = shares × totalAssets / totalSupply
```

### Running Tests

Run the full test suite:

```
forge test
```

Run tests with verbosity:

```
forge test -vv
```

Run invariant tests only:

```
forge test --match-test invariant
```

Generate a coverage report:

```
forge coverage
```

---

### 2. Conservative, Deterministic Math

* All conversions are proportional
* Rounding **always favors the vault**
* Rounding dust remains in the vault
* No user can extract value via rounding

| Operation       | Rounding |
| --------------- | -------- |
| convertToShares | DOWN     |
| convertToAssets | DOWN     |
| deposit         | DOWN     |
| mint            | UP       |
| withdraw        | UP       |
| redeem          | DOWN     |

---

### 3. Donation & Fee-on-Transfer Safety

* Deposits use **balance-delta accounting**
* Forced transfers are treated as donations
* Donations increase share value but **never mint shares**

---

### 4. Minimal Trust Assumptions

* ERC20 token is treated as adversarial
* No reliance on hooks, callbacks, or rebase behavior
* No admin access to funds

---

## Accounting Model

Let:

* `S = totalSupply()` (total shares)
* `A = totalAssets()` (underlying asset balance)

Ownership is proportional:

```
assets = shares × A / S
```

### Zero-Supply Bootstrap

* First depositor mints shares 1:1 with assets
* Initial exchange rate is exactly 1.0

---

## Security Model

The contract is built around **explicit invariants and threat modeling**.

### Key Guarantees

* Solvency: `totalAssets() == asset.balanceOf(vault)`
* Conservation: shares ↔ assets are always proportional
* No share inflation or deflation attacks
* Reentrancy-safe via CEI + ReentrancyGuard
* Pause disables all asset movement

### Documents

* `SPEC_V3.md`
* `INVARIANTS_V3.md`
* `THREAT_MODEL_V3.md`

These documents define what *must never break*.

---

## Testing Strategy

Tests are written using **Foundry** and follow an invariant-first approach.

### Test Coverage

* ERC4626 preview / execution parity
* Rounding correctness (up and down semantics)
* Donation and forced-transfer safety
* Pause semantics
* maxDeposit / maxMint / maxWithdraw / maxRedeem correctness
* Reentrancy resistance
* Solvency invariants under fuzzing

Example invariant:

```
totalAssets() >= convertToAssets(totalSupply())
```

---

## Tech Stack

* **Solidity** `^0.8.20`
* **OpenZeppelin Contracts** (ERC20, ERC4626)
* **Foundry** for testing

---

## Explicit Non-Goals

BankV3 intentionally does NOT:

* Generate yield or interest
* Deploy assets into strategies
* Support multiple assets per vault
* Support rebasing or ERC777 tokens
* Include governance or admin-controlled economics
* Implement upgrades or migrations

Any of the above belong in future versions.

---

## Asset Requirements

The underlying ERC20 **MUST**:

* Be non-rebasing
* Not be ERC777
* Not implement transfer hooks or callbacks
* Only change balances via transfers

Violating these assumptions breaks accounting invariants.

---

## Repository Structure

```
src/
 └─ BankV3.sol

test/
 └─ BankV3Test.t.sol

docs/
 ├─ SPEC_V3.md
 ├─ INVARIANTS_V3.md
 └─ THREAT_MODEL_V3.md
```

---

## Project Philosophy

This project is built as a **learning and demonstration artifact**, not a production deployment recommendation.

The goal is to show:

* How to design before coding
* How invariants drive implementation
* How ERC4626 should be implemented conservatively
* How to reason about financial smart contracts

---

## License

MIT

---

**BankV3 — A correctness-first ERC4626 vault.**
