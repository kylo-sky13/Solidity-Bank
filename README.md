# Bank v1 — Non-Custodial ETH Vault (MVP)

Bank v1 is a **minimal, security-first, non-custodial ETH vault** implemented in Solidity.

This project is designed as a **learning and engineering exercise** that follows real DeFi development and security practices rather than tutorial shortcuts.

The contract intentionally limits scope to ensure:

* Correct accounting
* Clear invariants
* Resistance to common EVM-level attacks
* Audit-grade test coverage

---

## ⚠️ Disclaimer

This code is **not audited** and **not intended for production use**.

It is a learning project meant to demonstrate *how a simple ETH vault should be built correctly*, not a finished financial product.

---

## High-Level Design

* ETH-only vault
* Per-user isolated balances
* No yield generation
* No lending
* No admin withdrawals
* No upgradeability

### User Capabilities

* Deposit their own ETH
* Withdraw **only their own balance**

### Owner Capabilities

* Pause and unpause the contract
* **Cannot**:

  * Withdraw user funds
  * Modify balances
  * Override accounting

---

## Supported Assets

| Asset   | Supported |
| ------- | --------- |
| ETH     | ✅ Yes     |
| ERC20   | ❌ No      |
| ERC4626 | ❌ No      |

---

## Roles & Permissions

### Users

* Any EOA or contract
* Can deposit ETH
* Can withdraw **only their own balance**

### Owner

* Can pause and unpause the contract
* Has no financial control over user funds

---

## Storage Layout (Canonical)

```solidity
mapping(address => uint256) internal balances;
uint256 internal totalDeposits;
bool internal paused;
address internal owner;
```

### Meaning

| Variable         | Description              |
| ---------------- | ------------------------ |
| `balances[user]` | ETH deposited by user    |
| `totalDeposits`  | Sum of all user balances |
| `paused`         | Emergency stop flag      |
| `owner`          | Pause controller         |

---

## Accounting Invariants

These invariants must **always** hold:

### 1. Balance Conservation

```
sum(balances[user]) == totalDeposits
```

### 2. Solvency

```
address(this).balance >= totalDeposits
```

### 3. User Safety

* Balances never go negative
* Users cannot withdraw more than their balance

### 4. Forced ETH Safety

* ETH sent via `selfdestruct` does **not** affect accounting

---

## Public Interface

### Deposit

```solidity
function deposit() external payable;
```

* Requires `msg.value > 0`
* Reverts if contract is paused
* Increases user balance and `totalDeposits`

---

### Withdraw

```solidity
function withdraw(uint256 amount) external;
```

* Requires `amount > 0`
* Requires `balances[msg.sender] >= amount`
* Reverts if contract is paused
* Uses **Checks-Effects-Interactions**
* Transfers ETH **after** state updates

---

### Balance View

```solidity
function balanceOf(address user) external view returns (uint256);
```

Returns the current ETH balance of a user.

---

## Emergency Controls

```solidity
function pause() external;
function unpause() external;
```

* Only callable by the owner
* Disables deposits and withdrawals
* Does **not** affect existing balances

---

## ETH Handling

* Direct ETH transfers are rejected
* Only `deposit()` accepts ETH
* Forced ETH via `selfdestruct` is handled safely

```solidity
receive() external payable {
    revert("Use deposit()");
}
```

---

## Security Considerations

* Solidity `^0.8.20` (checked arithmetic)
* Checks-Effects-Interactions enforced
* External ETH transfers occur after state updates
* No loops over users
* No floating-point math
* No unchecked arithmetic
* No hidden trust assumptions

---

## Testing

The project uses **Foundry** and includes:

### Unit Tests

* Deposit increases balances
* Withdraw decreases balances
* Cannot withdraw more than balance
* Pause blocks deposits and withdrawals

### Attack Tests

* Reentrancy attack fails
* Forced ETH does not break accounting

### Invariant Tests

* Balance conservation holds
* Contract solvency always holds

---

## Running Tests

```bash
forge install
forge test -vvvv
```

Run invariant fuzzing:

```bash
forge test --ffi --fuzz-runs 10000
```

---

## Project Status

**Bank v1 is complete.**

No additional features will be added to this version.

### Out of Scope (Future Versions)

* ERC20 support
* ERC4626-style vault shares
* Multi-asset accounting

These features are intentionally excluded to preserve the simplicity and security focus of v1.
