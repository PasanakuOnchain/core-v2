# 0001. Pull-claim payouts

- Status: Accepted
- Date: 2026-06-10

## Context

Each round tick must deliver `(N - 1) × amount` in ERC20 principal to the round recipient. Miss penalties must also leave the pool ledger and reach the protocol treasury (`owner()`). Two delivery models were available:

1. **Push** — `tick` transfers ERC20 directly to the recipient (and/or `owner()`) in the same transaction.
2. **Pull** — `tick` accrues balances; a later call transfers ERC20.

Recipients may be EOAs or contract wallets. Push transfers inside a complex settle loop increase reentrancy surface and gas for tick callers. Some recipients may prefer to batch claims or claim from a contract that validates internal rules first. The same gas and reentrancy concerns apply to pushing miss penalties to `owner()` on every tick.

## Decision

`tick` **accrues** principal to `_pending_payout[token_id][round_idx]` via `_accrue_recipient_payout`. Only `participants[round_idx]` may call `claim_round_payout(token_id, round_idx)` to receive the ERC20 transfer.

The pool index advances on `tick` even if the recipient has not claimed. Unclaimed principal remains in `pending_payout` until claimed.

Miss penalties follow the same pull model: `tick` debits `pool_escrow` and accrues to `_pending_penalties[asset]` via `_distribute_penalties` (logged in `PasanakuPenalties`). Anyone may later call permissionless `claim_penalties(asset)`, which transfers the accrued amount to the current `owner()` and emits `PenaltiesClaimed`. View: `pending_penalties(asset)`. `tick` never ERC20-transfers penalties to `owner()`.

## Consequences

### Positive

- Smaller, more predictable `tick` gas — no recipient or treasury ERC20 transfer in the settle path.
- Recipients control claim timing (batching, relaying, contract-wallet logic).
- Clear separation between settlement accounting and token delivery.
- Penalty claims are permissionless and can be batched per asset across ticks.

### Negative / risks

- UX burden — wallets must prompt claims after tick; principal can sit unclaimed.
- Indexers must track `pending_payout` and `pending_penalties`, not just `PasanakuTicked` / `PasanakuPenalties` events.
- Tests use `tick_and_claim` helper to assert recipient balances; penalty transfers require a separate `claim_penalties` call.
- Unclaimed penalties remain on the contract until someone calls `claim_penalties`.

## Alternatives considered

- **Push on tick** — simpler UX but higher tick gas and reentrancy coupling to recipient (and owner) addresses.
- **Automatic claim in tick for EOAs only** — discriminates against contract wallets; rejected.
