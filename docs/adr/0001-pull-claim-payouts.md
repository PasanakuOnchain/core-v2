# 0001. Pull-claim payouts

- Status: Accepted
- Date: 2026-06-10

## Context

Each round tick must deliver `(N - 1) × amount` in ERC20 principal to the round recipient. Two delivery models were available:

1. **Push** — `tick` transfers ERC20 directly to the recipient in the same transaction.
2. **Pull** — `tick` accrues to `pending_payout`; recipient calls `claim_round_payout` later.

Recipients may be EOAs or contract wallets. Push transfers inside a complex settle loop increase reentrancy surface and gas for tick callers. Some recipients may prefer to batch claims or claim from a contract that validates internal rules first.

## Decision

`tick` **accrues** principal to `_pending_payout[token_id][round_idx]` via `_accrue_recipient_payout`. Only `participants[round_idx]` may call `claim_round_payout(token_id, round_idx)` to receive the ERC20 transfer.

The pool index advances on `tick` even if the recipient has not claimed. Unclaimed principal remains in `pending_payout` until claimed.

## Consequences

### Positive

- Smaller, more predictable `tick` gas — no recipient transfer in the settle path.
- Recipients control claim timing (batching, relaying, contract-wallet logic).
- Clear separation between settlement accounting and token delivery.

### Negative / risks

- UX burden — wallets must prompt claims after tick; principal can sit unclaimed.
- Indexers must track `pending_payout`, not just `PasanakuTicked` events.
- Tests use `tick_and_claim` helper to assert recipient balances.

## Alternatives considered

- **Push on tick** — simpler UX but higher tick gas and reentrancy coupling to recipient addresses.
- **Automatic claim in tick for EOAs only** — discriminates against contract wallets; rejected.
