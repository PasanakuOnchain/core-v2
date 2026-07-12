# 0003. Stale pending exit

- Status: Accepted
- Date: 2026-06-10

## Context

A pool remains **pending** until ten members join. If recruitment stalls, participants have `pledge(amount)` locked in `collateral_in_use` with no round activity and no `_unlock_collateral_in_use` path from the normal lifecycle.

Without an exit valve, capital stays pledged indefinitely on abandoned pools. A global admin cancel would reintroduce trusted intervention and griefing (admin removes participants).

## Decision

After `created + stale_time`, any participant in a still-pending pool may call `leave_pasanaku(token_id)`:

- Unlocks that participant’s pledged collateral via `_unlock_participant_collateral_in_use`.
- Removes them from `pasanaku.participants` via `_remove_from_array`, which **shifts subsequent members down** so remaining participants keep their relative join order (not swap-with-last).
- Emits `PasanakuLeft`.

`stale_time` defaults to **7 days** at deploy. Owner may set **3 to 7 days** via `set_stale_time`. ERC-1155 `uri()` exposes a **stale** metadata state when the window has elapsed.

Join remains open for remaining participants until the pool fills or all leave.

## Consequences

### Positive

- Capital efficiency — stalled pools do not trap collateral forever.
- Permissionless per-participant exit; no admin refund button.
- Bounded wait before exit (configurable 3–7 days).

### Negative / risks

- Partial abandonment — pool may shrink (e.g. 4 → 3 members) rather than fully cancel.
- Owner controls stale window bounds — trust assumption on parameter choice.
- Integrators must monitor pending age and prompt leave or recruitment.

## Alternatives considered

- **Auto-refund all participants at stale time** — requires keeper or admin trigger; rejected.
- **Fixed 7-day non-configurable window** — less operational flexibility for deployments.
- **Forfeit pledge on leave** — overly punitive for recruitment failure; rejected.
