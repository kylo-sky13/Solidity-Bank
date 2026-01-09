# BankV4 — ERC4626 Vault with External Strategy

BankV4 is a security-first ERC4626 vault that supports external strategy deployment while preserving strict ERC4626 accounting guarantees.

This version focuses on:
- Explicit asset movement
- No hidden share minting or burning
- Loss and gain socialization via price-per-share (PPS)
- Strong unit tests and invariant tests (Foundry-style)


## Repository Structure

```
src/
├── strategy/
│   └── MockStrategy.sol
└── BankV4.sol

test/
├── Invariant/
│   └── BankV4Invariant.t.sol
└── BankV4Test.t.sol
```

## Core Contracts

### `BankV4.sol`

An ERC4626 vault with manual strategy integration.

#### Key Properties
- ERC4626 preview ↔ execution parity
- No auto-deploy on deposit
- Strategy gains/losses reflected via PPS
- Withdrawals unwind strategy only when needed
- No share inflation

#### Trust Model
- Strategy must report `totalAssets()` honestly
- Strategy insolvency is surfaced via reverts
- Vault never mints or burns shares outside ERC4626 logic

### `MockStrategy.sol`

A minimal external strategy used for testing.

#### Features
- Internal accounting (`managedAssets`)
- Manual `simulateGain()` and `simulateLoss()`
- Explicit insolvency modeling
- Vault-only access control

This strategy is intentionally simple to make vault invariants observable.

## Tests

### Unit Tests — `BankV4Test.t.sol`

Covers deterministic behavior such as:
- Deposits mint correct shares
- Deposits do NOT auto-deploy to strategy
- Manual deployment correctness
- Withdrawals using idle assets first
- Strategy unwinding on withdrawal
- Loss socialization across users

### Invariant Tests — `BankV4Invariant.t.sol`

Uses Foundry's invariant framework with a Handler pattern.

#### Handler (`BankV4Handler`)

Defines all fuzzable actions:
- `deposit`
- `withdraw`
- `deploy`
- `gain`
- `loss`

#### Invariants

Checked after every fuzz sequence:

```solidity
invariant_totalAssetsEqualsIdlePlusStrategy
invariant_noShareInflation
```

These ensure:
- Vault accounting always balances
- Shares are never inflated beyond assets

## Running Tests

### Run All Tests

```bash
forge test -vvv
```

### Run Only Unit Tests

```bash
forge test --match-path test/BankV4Test.t.sol -vvv
```

### Run Only Invariant Tests

```bash
forge test --match-path test/Invariant/BankV4Invariant.t.sol -vvv
```

### Run Invariant Tests with Coverage

```bash
forge coverage --match-path test/Invariant/BankV4Invariant.t.sol
```

> **Note:** High revert counts during invariant testing are expected and correct.