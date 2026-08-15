# Rounds

Fund each contribution window, settle with tick, and claim your payout when it is your turn.

## Goal

Complete every round: obligors deposit the per-round amount, someone ticks after the time gate, and the recipient pulls the pot.

## Roles each round

| Role | Who | Action |
| ---- | --- | ------ |
| Recipient | One member (shuffled position for this round) | Does not owe the per-round deposit; claims the pot after tick |
| Obligor | Everyone else | Deposits exactly the per-round amount |

A three-participant circle runs three rounds; six runs six; nine runs nine; twelve runs twelve. Each member is recipient exactly once.

## Steps

1. Check whether you are the **recipient** or an **obligor** for the current round.
2. If you are an obligor, **deposit** the per-round amount (approve the asset first if needed). Anyone may deposit on behalf of a participant.
3. After at least **28 days** since start or the last successful tick, anyone may **tick** to settle the round.
4. The recipient **claims** the pending payout when ready. You do not have to claim before the next tick.
5. Repeat until the final tick ends the circle.

In the app, these actions usually live under **Mine** or a started-pool detail view.

## What the protocol does

Round deposits are liquid assets attributed to the pool’s escrow for that round. Tick settles the round into a **pending payout** for the recipient — it does not send funds automatically. Claim pulls that balance to the recipient. The pool can advance even if earlier payouts are still unclaimed.

If someone misses a deposit, locked collateral can cover the obligation; see [Misses and stale pools](/user/misses-and-stale).

## Timing

| Rule | Detail |
| ---- | ------ |
| Minimum interval | 28 days between ticks (or since start for the first tick) |
| Who can tick | Anyone (permissionless) |
| Who can claim | The recipient for that round’s pending payout |

## Common mistakes

- Depositing when you are the recipient — you are not an obligor that round.
- Believing tick pays you directly — you must **claim**.
- Blocking yourself waiting to claim before the next round — ticks can proceed anyway.
- Missing the deposit and assuming nothing happens — collateral and a small reserve penalty may apply.

## See also

- [Create and join](/user/create-and-join)
- [Yield and end](/user/yield-and-end)
- [Misses and stale pools](/user/misses-and-stale)
- Implementation: [Rounds](/guide/rounds)
