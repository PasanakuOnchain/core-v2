# ERC-4626 collateral accounting discussion

## User

I’m updating `src/Pasanaku.vy`, the core smart contract, to integrate a single asset and vault.

The idea is that users can deposit yield-bearing collateral. Once they enter a Pasanaku, they need a certain amount of collateral based on the Pasanaku amount. The locked collateral remains yield-bearing, but its yield will be distributed to all participants at the end of the Pasanaku using a custom distribution algorithm.

Should I move shares around or directly move assets? I previously had two mappings: one representing collateral as shares and another representing collateral as assets. Having two data structures tracking the same thing seems like an anti-pattern in smart contracts. What do you think?

## Assistant

Use vault shares as the canonical accounting unit. Do not maintain live asset and share balances for the same collateral.

ERC-4626 assets are not stable bookkeeping units: as yield accrues, the asset value changes without any transaction. Maintaining both would eventually cause inconsistencies.

Recommended model:

```vyper
_free_shares: HashMap[address, uint256]
_locked_shares: HashMap[uint256, HashMap[address, uint256]]
_principal_assets: HashMap[uint256, HashMap[address, uint256]]
```

These are not duplicate ledgers:

- `free_shares`: withdrawable collateral.
- `locked_shares`: shares assigned to a specific Pasanaku.
- `principal_assets`: the asset-denominated principal entitlement or cost basis used to separate principal from yield.

Flows:

1. Deposit assets into the vault and credit the returned shares.
2. When joining, convert the required asset collateral using `previewWithdraw(required_assets)`, then move that quantity internally from free shares to pool-locked shares.
3. Do not transfer vault shares externally while locking or unlocking. The contract owns all vault shares; only its internal accounting changes.
4. For slashing or asset payouts, call `vault.withdraw(assets, ...)` and deduct the actual shares burned from that pool’s locked balance.
5. At the end, separate principal from yield:
   - `principal_shares = previewWithdraw(remaining_principal_assets)`
   - `yield_shares = locked_shares - principal_shares`
   - Return principal shares to the original owner.
   - Distribute yield shares using the custom algorithm.
6. Users redeem their credited shares for assets when they withdraw.

Distributing shares is preferable to redeeming and redistributing assets because it avoids unnecessary vault withdrawals, keeps rewards yield-bearing, and reduces rounding and transfer operations.

The current draft already exposes unit-mismatch risks. `_collateral` and `_collateral_in_use` are documented as shares:

```vyper
# @dev Mapping: account address -> Total collateral (as shares)
_collateral: HashMap[address, uint256]

# @dev Mapping: Account address -> Collateral in use (as shares)
_collateral_in_use: HashMap[address, uint256]
```

But withdrawal compares their difference against an asset amount:

```vyper
preview_shares: uint256 = staticcall vault.previewWithdraw(assets)
collateral: uint256 = self._collateral[owner]
assert collateral >= preview_shares

collateral_in_use: uint256 = self._collateral_in_use[owner]
assert collateral > collateral_in_use
assert collateral - collateral_in_use >= amount
```

That final comparison must be shares versus `preview_shares`, not shares versus assets. Similar conversions are required throughout slashing and pledge calculations.

Two important policy decisions remain:

- Define whether pool yield begins at join or only when the Pasanaku starts. Starting at the latter is recommended; pending-pool yield should remain with the depositor.
- ERC-4626 vaults can lose value. If locked shares become worth less than required principal, the protocol needs an explicit rule: top-up, proportional loss, reserve coverage, or pool-start/settlement failure.

The short answer is: hold and account in shares, express obligations in assets, convert only at the operation boundary, and store an asset basis only where needed to distinguish principal from distributable yield.

---

## User

For those three mappings you recommended, can you go into detail about what each type represents?

## Assistant

The three mappings form a partition of ownership plus an asset-denominated accounting reference.

### 1. `_free_shares`

```vyper
_free_shares: HashMap[address, uint256]
```

- **Key:** Collateral owner.
- **Value:** Raw ERC-4626 share units owned by that user and not assigned to any Pasanaku.
- **Purpose:** Determines how many shares can be withdrawn or committed to a pool.

Operations:

- Vault deposit: increase by shares minted.
- Join or create: decrease by shares locked.
- Pool completion: increase by returned principal shares and allocated yield shares.
- Withdrawal: decrease by shares burned.

Example: Alice deposits 1,000 assets and receives 900 vault shares:

```text
_free_shares[Alice] = 900
```

This balance should never be denominated in underlying assets.

### 2. `_locked_shares`

```vyper
_locked_shares: HashMap[uint256, HashMap[address, uint256]]
```

- **First key:** Pasanaku ID.
- **Second key:** Participant.
- **Value:** Raw vault shares belonging to that participant but assigned as collateral to that specific pool.
- **Purpose:** Isolates collateral between concurrent Pasanakus.

Locking is only an internal reassignment:

```text
_free_shares[user] -= shares
_locked_shares[pool_id][user] += shares
```

The ERC-4626 shares themselves remain owned by the Pasanaku contract.

When collateral is slashed:

1. Withdraw the required assets from the vault.
2. Observe how many shares the vault burned.
3. Deduct those shares from this mapping.

This pool-specific structure is important. A global `_collateral_in_use[user]` cannot identify which pool is allowed to slash which shares.

### 3. `_principal_assets`

```vyper
_principal_assets: HashMap[uint256, HashMap[address, uint256]]
```

A more precise name would be:

```vyper
_locked_asset_basis: HashMap[uint256, HashMap[address, uint256]]
```

- **First key:** Pasanaku ID.
- **Second key:** Participant.
- **Value:** Raw underlying asset units that the participant should recover before any remaining value is classified as yield.
- **Purpose:** Provides the fixed reference required to separate principal from yield.

It is not a live collateral balance. Its value does not increase when the vault earns yield.

Example:

```text
_locked_shares[pool_id][Alice] = 600 shares
_locked_asset_basis[pool_id][Alice] = 600 assets
```

Later, each share becomes worth `1.2 assets`:

```text
600 shares = 720 assets
```

At pool completion:

```text
principal_shares = vault.previewWithdraw(600 assets) = 500 shares
yield_shares = 600 locked shares - 500 principal shares = 100 shares
```

Therefore:

- Alice recovers 500 shares representing her 600-asset principal.
- The custom algorithm distributes the remaining 100 shares, worth 120 assets.

If Alice was slashed by 100 assets during the pool:

```text
_locked_asset_basis[pool_id][Alice] -= 100
```

The vault withdrawal also burns shares from her `_locked_shares` entry.

### Core invariant

Every accounted vault share must belong to exactly one bucket:

```text
vault.balanceOf(Pasanaku)
    = all free shares
    + all pool-locked shares
    + any separately accounted protocol or payout shares
```

`_free_shares` and `_locked_shares` represent ownership. `_locked_asset_basis` represents an economic entitlement, not another balance. That distinction avoids the duplicated asset/share ledger problem.

---

## User

What would you remove from the core smart contract?

## Assistant

I would remove the state and interface left over from the multi-asset, non-vault design.

### Definitely remove

#### 1. Per-Pasanaku asset storage

```vyper
struct Pasanaku:
    token_id: uint256
    asset: address
    assets: uint256
```

- Remove `asset`: every pool uses `_ASSET`.
- Remove `token_id`: the mapping key already identifies it.
- Rename `assets` to something explicit such as `round_assets`.

#### 2. Asset arguments and validation

Remove `asset` from:

- `create_pasanaku`
- Collateral getters
- Events
- Internal settlement functions

Also remove `_SUPPORTED_ASSETS`, `supported_assets()`, and all “unsupported asset” checks. These are obsolete with one immutable asset.

#### 3. Per-asset active pool tracking

Remove `_active_pasanaku_by_asset` and `active_pasanaku_for_asset()`. If the count is still needed, use a single scalar `_active_pasanaku_count`.

#### 4. Old collateral accounting

Replace or remove:

```vyper
_collateral: HashMap[address, uint256]
_collateral_in_use: HashMap[address, uint256]
_slashed_from_in_use: HashMap[uint256, HashMap[address, uint256]]
```

Use the partitioned model instead:

- `_free_shares`
- `_locked_shares[pool_id][participant]`
- `_locked_asset_basis[pool_id][participant]`

With per-pool remaining locked shares, `_slashed_from_in_use` is unnecessary.

#### 5. Redundant `owner` withdrawal parameter

Currently callers must provide `owner`, but the contract requires:

```vyper
def withdraw(assets: uint256, receiver: address, owner: address) -> uint256:
    assert assets > 0
    assert msg.sender == owner
```

Without an allowance or operator system, `owner` is always `msg.sender`. Remove it from `withdraw` and `redeem`.

#### 6. `_MIN_FEE`

A `uint256` is always at least zero, so `_MIN_FEE = 0` and `fee >= _MIN_FEE` add nothing.

### Consider removing

#### `_successful_obligated_deposits`

```vyper
_deposited_for_pasanaku: HashMap[uint256, HashMap[uint256, HashMap[address, bool]]]
_successful_obligated_deposits: HashMap[uint256, HashMap[address, uint256]]
```

The count is derived from the per-round booleans. Because participant and round counts are bounded at 12, the distribution algorithm could calculate it at completion. Keep the count only if avoiding that loop materially matters.

#### ERC-1155 membership

Participant membership already exists in `Pasanaku.participants`. The ERC-1155 implementation, metadata, minting, and permanently reverting transfer functions add substantial contract surface.

Remove it if no external integration genuinely needs tokenized membership. If membership NFTs are part of the product, keep the complete implementation.

### Do not automatically remove

- `_deposited_for_pasanaku`: required to prevent duplicate payments and detect defaults.
- `_pool_escrow`: keep if round contributions remain liquid underlying assets.
- `_pending_payout`: keep for safe pull-based claims.
- Both `withdraw` and `redeem`: they provide useful asset-exact and share-exact withdrawal semantics.

The current file also contains many stale references such as `_SUPPORTED_ASSETS`, `_PARTICIPANT_COUNT`, `pasanaku.amount`, `asset`, and `vault`. It is presently a partially merged architecture rather than a compilable implementation; those old-model references should be removed consistently.


## Chat

```bash
agent --resume=f7df8f01-3a99-4c8c-b8c3-d5a81dfc9cf0
```
