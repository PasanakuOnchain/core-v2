# 04. Pool lifecycle

A pasanaku pool moves through distinct phases from creation to collateral release.

## Phase 1 — Collateral funding

Before creating or joining any pool for asset `A`, a participant calls `add_collateral(A, amount)` to credit their collateral ledger. Only **free collateral** (`collateral - collateral_in_use`) can fund new pools or be withdrawn.

## Phase 2 — Create and join (pending)

1. **Create** — `create_pasanaku(asset, amount)` with `msg.value >= fee()` (ETH creation fee; default 0). Creator becomes participant 0. `pledge(amount)` moves from free to in-use collateral.
2. **Join** — Up to nine others call `join_pasanaku(token_id)`, each locking `pledge(amount)`.
3. **Pending state** — `started == 0`, fewer than ten members. Multiple pending pools per asset may coexist.

### Stale pending exit

If the pool never reaches ten members before `created + stale_time`:

- Pool becomes **stale** (default stale window: 7 days; owner may set 3–7 days via `set_stale_time`).
- Any participant may call `leave_pasanaku(token_id)` to unlock their pledge and leave.
- Removal preserves relative join order of remaining participants (shift-down, not swap-with-last).
- Emits `PasanakuLeft`. Remaining participants can still join if the pool is not abandoned entirely.

See [ADR-0003: Stale pending exit](../adr/0003-stale-pending-exit.md).

## Phase 3 — Auto-start

When the tenth member joins, `_start_pasanaku` runs automatically:

- Sets `started` and `updated` timestamps
- Increments `active_pasanaku_for_asset(asset)`
- Mints soulbound ERC-1155 membership (amount 1) to each participant

Membership is fixed — no further joins.

## Phase 4 — Ten rounds

For round index `k` (0 … 9):

| Role | Action |
|------|--------|
| **Recipient** | `participants[k]` — does not deposit this round |
| **Obligors** | Other nine call `deposit_to_pasanaku(amount, token_id)` |
| **Anyone** | After `updated + 40 days`, call `tick(token_id)` |
| **Recipient** | Call `claim_round_payout(token_id, k)` to receive accrued principal |

Each tick settles round `k`, accrues `(N-1) × amount` to `pending_payout`, accrues miss penalties to `pending_penalties(asset)` (later claimed via permissionless `claim_penalties`), and advances `index`.

## Phase 5 — End and unlock

On the tick that settles round 9 (`round_idx == N-1`):

- Pool sets `ended`
- `_unlock_collateral_in_use` releases pledged collateral (net of prior slashes)
- `active_pasanaku_for_asset` decrements
- ERC-1155 `uri()` reflects **ended** state

Participants may `withdraw_collateral` for any remaining free balance.

## Timeline summary

```
add_collateral → create/join (pending) → [optional: stale → leave_pasanaku]
              → 10th join (start) → 10 × (40-day window + tick + claim)
              → end → unlock collateral
```

---

> **Implemented today**
>
> Full lifecycle including stale exit is in `src/Pasanaku.vy`. Visual diagram: [protocol-flow.md](../protocol-flow.md). Constants: N=10, 40-day windows, stale_time 3–7 days.
