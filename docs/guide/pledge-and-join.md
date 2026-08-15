# Pledge and join

Joining a pool converts a free-share balance into pool-locked collateral sized by `pledge`.

## Pledge math

For `N ∈ {3, 6, 9, 12}`:

```text
principal = round_assets * N
penalty_headroom = principal * _MISS_PENALTY_BPS / 10_000
pledge = principal + penalty_headroom
```

`_MISS_PENALTY_BPS` is `100` (1%). The pure view `pledge(round_assets, participant_count)` returns this asset amount after validating `N`.

## `_lock_pledge`

Create and join both call `_lock_pledge`:

1. Compute the asset pledge.
2. Convert with `vault.previewWithdraw(assets)` → required shares.
3. Require enough `_free_shares[participant]`.
4. Move shares: free ↓, `_locked_shares[token_id][participant]` ← required shares.

At this stage `locked_asset_basis` is still zero. Basis is written later in `_start_pasanaku` after pre-start normalization.

## `create_pasanaku`

```text
create_pasanaku(round_assets, participant_count) -> token_id
```

Payable. Behavior:

1. Validate `round_assets > 0` and participant count.
2. Require `msg.value >= _fee`; refund excess native currency.
3. Allocate `token_id` from `_counter`.
4. Snapshot `yield_fee` and `stale_time` onto the pool struct.
5. Append the creator as the first participant and lock their pledge.

Emits `PasanakuCreated`. The pool remains pending (`started == 0`) until the roster fills.

## `join_pasanaku`

Open only while:

- `started == 0`
- `block.timestamp < created + stale_time`
- caller not already in the roster
- roster length `< participant_count`

Locks the caller's pledge, appends them, emits `PasanakuJoined`. When length equals `participant_count`, calls `_start_pasanaku`.

## Pending pools and `leave_pasanaku`

A pool is pending while `started == 0`. After `created + stale_time`, it becomes exit-only:

- new joins revert (`pasanaku is stale`)
- existing participants may `leave_pasanaku`

Leave returns that participant's locked shares to free shares, clears their (still-zero) asset basis, removes them from the roster via swap-and-pop, and emits `PasanakuLeft`.

`stale_time` defaults to seven days and is owner-configurable between three and seven days via `set_stale_time`. Updates apply only to pools created after the change—each pool snapshots the value at creation.

## See also

- [Start and shuffle](./start-and-shuffle.md)
- `CONTEXT.md` — Pledge, Pending pools
- `tests/unitary/pasanaku/test_lifecycle.py`, `test_deposit.py`
