# 🏦 BankV2 — Strict ERC20 Vault with Invariant-Driven Security

`BankV2` is a minimal, security-focused ERC20 vault that supports **multi-token deposits and withdrawals** with **strict accounting guarantees**.

The contract is intentionally conservative: no yield, no shares, no upgradeability — only **correct ERC20 custody** enforced through invariants and adversarial testing.

---

## ✨ Key Properties

* Multi-token ERC20 vault
* Exact accounting per user per token
* No admin fund access
* Fee-on-transfer tokens rejected
* ERC777-style callbacks blocked
* Reentrancy-safe withdrawals
* Pause as a pure circuit breaker
* Invariant-tested with Foundry

---

## 🚫 Explicit Non-Goals

BankV2 does **not** support:

* ETH deposits
* ERC4626 or vault shares
* Rebasing tokens
* Fee-on-transfer tokens
* ERC777 tokens
* Upgradeability
* Admin withdrawals
* Yield generation

All exclusions are **intentional** and enforced.

---

## 🪙 Accounting Model

### Storage Layout

```solidity
mapping(address => mapping(address => uint256)) balances;
// user => token => amount

mapping(address => uint256) totalBalances;
// token => total deposited
```

---

## 📐 Core Invariants

For every ERC20 token `T`:

### 1. Conservation of Balances

```
Σ balances[user][T] == totalBalances[T]
```

### 2. Solvency

```
IERC20(T).balanceOf(address(this)) >= totalBalances[T]
```

### 3. Token Isolation

Operations on token `T` never affect accounting for token `U ≠ T`.

### 4. Pause Safety

When paused:

* Deposits revert
* Withdrawals revert
* No state changes occur

These properties are enforced using **fuzzed invariant tests**.

---

## 🔐 Security Design

### ERC20 Safety

* Uses OpenZeppelin `SafeERC20`
* Explicitly rejects:

  * Fee-on-transfer tokens
  * Tokens returning `false`
  * Tokens transferring incorrect amounts

### Reentrancy Defense

* Withdrawals protected by `ReentrancyGuard`
* State updates occur **before** external calls

### Admin Controls

* Owner can pause / unpause only
* Owner cannot move funds or edit balances
* Pause is strictly non-custodial

---

## 🔧 Public Interface

### Deposit

```solidity
function depositToken(address token, uint256 amount) external;
```

**Requirements**

* Contract not paused
* `token != address(0)`
* `amount > 0`
* Exact amount received

---

### Withdraw

```solidity
function withdrawToken(address token, uint256 amount) external;
```

**Requirements**

* Contract not paused
* `amount > 0`
* Sufficient balance
* Reentrancy-safe

---

### Views

```solidity
function balanceOf(address user, address token) external view returns (uint256);
function totalBalanceOf(address token) external view returns (uint256);
```

---

## 🧪 Testing Strategy

Security is validated through **unit, attack, and invariant tests**.

### Unit Tests

* Deposit increases balances
* Withdraw decreases balances
* Insufficient withdrawals revert
* Token isolation holds
* Pause blocks state changes

### Attack Tests

* Fee-on-transfer token deposit reverts
* ERC20 returning `false` is rejected
* ERC777-style callback attack fails
* Reentrancy during withdraw fails

### Invariant Tests (Fuzzed)

* Sum of balances equals total balance
* Vault always solvent
* No state changes while paused

---

## 📂 Repository Structure (V2 Only)

```
src/
 └── BankV2.sol

test/
 ├── BankV2Test.t.sol
 ├── BankV2AttackTest.t.sol
 ├── BankInvariantV2.t.sol
 ├── BankV2Handler.sol
 ├── mocks/
 │   ├── ERC777LikeERC20.sol
 │   ├── ERC777CallbackAttacker.sol
 │   ├── FalseReturnERC20.sol
 │   ├── FeeOnTransferERC20.sol
 │   ├── ReentrantWithdrawer.sol
 │   └── ReentrancyAttacker.sol
```

Mocks are **test-only** and used to simulate hostile ERC20 behavior.

---

## 🛠 Tooling

* Solidity `^0.8.20`
* Foundry
* OpenZeppelin Contracts

Run all tests:

```bash
forge test
```

Run only invariant tests:

```bash
forge test --match-contract BankV2InvariantTest
```

---

## ⚠️ Disclaimer

This repository is for educational and research purposes only.
The contracts have **not** been formally audited.

---

## 🧠 Philosophy

> Simple contracts with explicit invariants are harder to break than complex contracts with hidden assumptions.

BankV2 is designed to be **provable, minimal, and hostile-environment safe**.
