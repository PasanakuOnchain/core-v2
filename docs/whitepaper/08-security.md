# 08. Security

## Design intent

Pasanaku aims to provide:

- **Collateralized obligations** — join locks `pledge(amount)`; misses slash collateral while crediting recipients.
- **Permissionless liveness** — anyone may `tick` after the 40-day window.
- **Fixed membership** — no late joins; transfers disabled on ERC-1155.
- **Per-pool isolation** — `pool_escrow` prevents cross-pool ERC20 mixing for the same asset.

## Trust and privilege boundaries

| Party | Can do | Cannot do |
|-------|--------|-----------|
| **Participants** | Collateral, create/join, deposit, claim, leave stale pending | Change others’ payouts; tick early |
| **Any address** | `tick` after window; `claim_penalties` | Set fees, collect ETH, alter stale time |
| **Owner** | `set_fee`, `set_stale_time`, `collect_fees`; receives penalties via `claim_penalties` | Force tick; redirect recipient payouts; pause |

## Threat model

### Missed obligor deposits

Primary expected failure mode. Mitigation: slash `amount + penalty` from collateral; recipient still credited `amount` per obligor.

### Concurrent pools same asset

Multiple active pools share one ERC20 token but separate `pool_escrow` ledgers. One pool’s tick must not spend another’s deposits — enforced by per-`token_id` accounting.

### No admin tick

Owner cannot advance rounds. If nobody calls `tick`, rounds stall until someone does — integrators should relay or incentivize ticks.

### ERC20 assumptions

Only standard transfer semantics. Fee-on-transfer or rebasing tokens can desync internal balances from actual holdings.

### Pull-claim UX

Recipients who never call `claim_round_payout` leave principal in the contract. Miss penalties similarly accrue until someone calls `claim_penalties`. Funds are not lost, but UX depends on wallets prompting claims.

### Stale pending abandonment

Unfilled pools do not auto-refund — each participant must `leave_pasanaku` after stale time.

## Invariants (test-backed)

Preserved by the Titanoboa test suite:

- `pledge(amount)` matches `_pledge` / `pledge()` view.
- Successful tick accrues `(N - 1) × amount` to `pending_payout`.
- Missed obligor: slash `amount + penalty`, penalties accrue to `pending_penalties` (claimable to treasury), recipient credited `amount`.
- Only free collateral is withdrawable while `collateral_in_use > 0`.
- `active_pasanaku_for_asset` increments on start, decrements on end; no hard cap at 1.

## What is not guaranteed

- Not “fully trustless” — `owner()` receives fees and penalties.
- Not safe for arbitrary ERC20s.
- Not protected by pause or upgrade paths on deployed instances.

---

> **Implemented today**
>
> Threat model and invariants align with `src/Pasanaku.vy` and tests under `tests/`. See [README.md](../../README.md) — Security assumptions and Invariant-first testing.
