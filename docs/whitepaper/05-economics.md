# 05. Economics

This chapter defines the onchain money rules for a single pasanaku pool.

## Constants

| Constant | Value |
|----------|-------|
| Participants `N` | 10 |
| Rounds | 10 (one payout per participant) |
| Round window | 40 days |
| Miss penalty | 5 bps (0.05% of `amount` per missed obligor) |

## Per-round obligor deposit

Each non-recipient must transfer exactly `amount` (raw ERC20 units) via `deposit_to_pasanaku` during the active round window.

## Recipient payout

On a fully funded round, the recipient is credited:

```
recipient_payout = (N - 1) × amount = 9 × amount
```

Nine obligor principals. Credited to `pending_payout` on tick; delivered on `claim_round_payout`.

## Collateral pledge

Before create or join, the contract locks:

```
pledge(amount) = amount × N + amount × N × MISS_PENALTY_BPS / 10000
               = amount × 10 + amount × 10 × 5 / 10000
```

The first term covers ten round obligations; the second is penalty headroom for missed deposits.

## Miss behavior

If an obligor did not deposit before tick:

1. **Principal** `amount` is slashed from their collateral and credited toward the recipient payout.
2. **Penalty** `amount × 5 / 10000` is slashed and sent to `owner()`.
3. The recipient still receives full `amount` credit for that obligor — penalties do not reduce recipient principal.

## Worked example (USDC, 6 decimals)

`amount = 100_000_000` (100 USDC):

| Quantity | Value |
|----------|-------|
| Per-round obligor deposit | 100 USDC |
| Recipient payout (full round) | 900 USDC |
| Pledge lock | 1,000 USDC + 0.5 USDC penalty reserve |
| One miss at tick | Recipient gets 100 USDC from slash; 0.05 USDC penalty to treasury |

Over ten rounds, each participant pays nine obligor deposits and receives one recipient payout (900 USDC in this example), net of any collateral slashes.

## No lending yield

ERC20 sits in the contract as collateral or escrow. Pasanaku does not deploy assets to external protocols; there is no interest accrual onchain.

---

> **Implemented today**
>
> Formulas match `pledge()`, `_settle_round`, and `tick` in `src/Pasanaku.vy`. See [README.md](../../README.md) — Economics (formula-first).
