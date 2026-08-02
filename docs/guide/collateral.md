# Collateral shares

Vault shares are the ownership unit. The Pasanaku contract is the sole ERC-4626 shareholder for user collateral. Users never hold vault shares directly through this protocol path.

## Storage buckets

| Storage                               | Meaning                                            |
| ------------------------------------- | -------------------------------------------------- |
| `_free_shares[user]`                  | Withdrawable or pledgeable shares                  |
| `_locked_shares[token_id][user]`      | Shares committed to one pool                       |
| `_locked_asset_basis[token_id][user]` | Fixed underlying principal reference for that lock |
| `_pool_reserve_shares[token_id]`      | Miss-penalty shares owned by the pool              |

`locked_asset_basis` is an economic basis, not a live second balance. Share market value moves with the vault; basis changes only when principal (and miss penalty headroom) is slashed during settlement.

Locking and unlocking only reassign internal buckets. Assets cross the vault boundary when a user deposits, withdraws, or redeems free shares; when a miss pulls principal from locked shares; or when the owner later redeems accrued yield-fee shares.

## `deposit`

```text
deposit(assets, receiver) -> shares
```

1. Pull `assets` from `msg.sender` into the contract.
2. Approve and `vault.deposit(assets, self)`.
3. Credit returned shares to `_free_shares[receiver]`.

Emits `CollateralDeposited`.

## `withdraw`

```text
withdraw(assets, receiver) -> shares
```

Burns free shares for an **exact asset amount**:

1. `previewWithdraw(assets)` must fit the caller's free balance.
2. `vault.withdraw(assets, receiver, self)`.
3. Subtract the burned share count from `_free_shares[msg.sender]`.

Emits `CollateralWithdrawn`.

## `redeem`

```text
redeem(shares, receiver) -> assets
```

Burns an **exact free share amount**:

1. Require `_free_shares[msg.sender] >= shares`.
2. `vault.redeem(shares, receiver, self)`.
3. Debit free shares.

Emits `CollateralRedeemed`.

## What these functions cannot touch

Locked shares and pool reserve shares are invisible to `withdraw` / `redeem`. There is no user path to pull another participant's collateral or the pool reserve.

## Invariant checklist

When reasoning about a state transition, verify:

1. Share buckets still sum to `vault.balanceOf(self)` (ignoring any transient vault rounding the vault itself owns).
2. Liquid escrow / pending payout changes match ERC-20 balances held outside the vault.
3. Free-share decreases that are not vault burns must appear as locked or reserve increases.

## See also

- `CONTEXT.md` — Collateral shares
- `tests/unitary/pasanaku/test_collateral.py`
