# Pasanaku domain context

Terminology and accounting guardrails for contributors and agents.

## Source of truth

`src/Pasanaku.vy` and passing tests are canonical. Do not document the earlier
multi-asset or asset-denominated collateral model as current behavior.

## Pasanaku

A fixed-membership rotating savings pool identified by `token_id`.

- A creator configures exactly `6` or `12` participants.
- At start, the participant roster is shuffled using beacon randomness.
- There are `N` rounds and recipient `k` is shuffled `participants[k]`.
- The per-round obligation is `round_assets` in raw units of the deployment's
  single immutable ERC-20 asset.
- Membership becomes fixed when the pool starts.

Say “six-participant pasanaku” or “twelve-participant pasanaku,” not “variable
size between six and twelve.”

## Asset and vault

Each contract instance has one immutable `_ASSET` and one immutable ERC-4626
`_VAULT`. Pools do not select assets or vaults.

The constructor verifies `vault.asset() == asset`. Multiple pools can run
concurrently against the same vault; `token_id` scopes their locked shares,
reserve, escrow, and payouts.

## Collateral shares

Vault shares are the canonical ownership unit.

- `_free_shares[user]`: shares the user can withdraw or pledge.
- `_locked_shares[token_id][user]`: shares committed to one pool.
- `_locked_asset_basis[token_id][user]`: fixed underlying-asset principal
  reference. This is an economic basis, not a live balance.
- `_pool_reserve_shares[token_id]`: penalty shares owned by the pool.

Do not describe `locked_asset_basis` as duplicate asset collateral. Share value
changes with the vault; asset basis changes only when principal is slashed.

The core accounting invariant is:

```text
vault.balanceOf(Pasanaku)
  = all free shares
  + all locked shares
  + all pool reserve shares
```

Round escrow and pending payouts are liquid underlying assets and are separate
from this share invariant.

## Deposit, withdraw, and redeem

- `deposit(assets, receiver)` transfers underlying to the contract, deposits it
  into the vault, and credits returned shares to `receiver`.
- `withdraw(assets, receiver)` burns the caller's free shares for an exact asset
  amount.
- `redeem(shares, receiver)` burns an exact number of the caller's free shares.

Locked or reserve shares cannot be withdrawn through these user functions.

## Pledge

For `N` equal to `6` or `12`:

```text
principal = round_assets * N
penalty_headroom = principal * MISS_PENALTY_BPS / 10_000
pledge = principal + penalty_headroom
```

`MISS_PENALTY_BPS` is `5`, meaning 0.05%, not 5%.

Create and join convert the asset obligation with `vault.previewWithdraw` and
move the required shares from free to pool-locked accounting.

## Yield start

Pool yield begins at `_start_pasanaku`, not at create or join.

At start, the contract recomputes the shares needed for the pledge:

- Pre-start appreciation returns to the participant's free shares.
- A pre-start loss requires enough free shares to top up; otherwise start
  reverts.
- The participant roster is shuffled before recipient positions become final.
- The fixed asset basis is recorded only after this normalization.

## Round deposits and pull payouts

Anyone may fund an obligor's round deposit via
`deposit_to_pasanaku(round_assets, token_id, participant)`. Assets are pulled
from the caller; credit is recorded for `participant`.

- Contributions are liquid ERC-20 attributed to `_pool_escrow[token_id]`.
- After 40 days, permissionless `tick` settles the round.
- Tick normally accrues `(N - 1) * round_assets` to
  `_pending_payout[token_id][round_idx]`. If an underwater misser cannot cover
  the full obligation, tick accrues the liquid deposits plus assets recovered
  from that participant's remaining shares.
- The recipient calls `claim_round_payout` to pull the assets.
- The pool may advance while earlier payouts remain unclaimed.

Do not say that tick transfers the payout directly to the recipient.

## Miss and pool reserve

If an obligor misses:

1. The contract prices principal plus the 5-bps penalty with one
   `previewWithdraw` call so rounding remains aligned.
2. If locked shares cover the result, the vault withdraws `round_assets` into
   liquid pool escrow and the remaining penalty shares move into
   `_pool_reserve_shares[token_id]`.
3. If locked shares are insufficient, all remaining shares are redeemed into
   escrow, the participant's locked shares and basis are cleared, and tick
   continues with the partial recovery.

The contract owner does not receive miss penalties. The owner receives native
creation fees through `collect_fees` and the configured yield fee when a pool
ends.

## End settlement

The last tick settles collateral in this order:

1. Calculate shares needed to return each participant's remaining asset basis.
2. Use reserve shares to cover principal shortfalls.
3. If reserve is insufficient, allocate it proportionally across shortfalls.
4. Collect participant yield and unused reserve as surplus.
5. Calculate the fee from surplus shares and redeem those shares directly to
   the owner as underlying assets.
6. Distribute the remaining yield by shuffled position using
   `distributable_yield * (i + 1) // total_weight`, where
   `total_weight = participant_count * (participant_count + 1) // 2`.
   Integer dust goes to the final participant.
7. Clear locked shares, asset bases, and pool reserve.

Round or end settlement does not revert solely because the vault lost value.

## Pending pools

A pool is pending while `started == 0`. Each pool snapshots `stale_time` when
it is created. After `created + stale_time`, the pool becomes exit-only: new
joins revert and existing participants may leave individually. Leaving returns
that participant's locked shares to free shares.

`stale_time` defaults to seven days and is owner-configurable between three and
seven days. An update applies only to pools created after the change.

## ERC-1155 membership

At start, every participant receives one ERC-1155 membership receipt.
Transfers and approvals revert, so the receipt is soulbound. `uri(token_id)`
reflects not-created, pending, stale, ongoing, and ended states.

## Quick constants

- Participant counts: `6` or `12`
- Miss penalty: `5` bps
- Round duration: `40 days`
- Stale bounds: `3` to `7 days`
- Creation fee cap: `0.001 ETH`
- Yield fee cap: `505` bps
- ERC-1155 amount per participant: `1`

Write **onchain** as one word.
