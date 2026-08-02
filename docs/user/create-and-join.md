# Create and join

Open a new pasanaku or join one that is still filling.

## Goal

Lock your pledge into a six- or twelve-participant pool and reach a full roster so rounds can start.

## Steps — create

1. Supply enough [collateral](/user/collateral) for the pledge.
2. Choose **participants**: exactly **6** or **12**.
3. Set the **per-round amount** (each obligor’s deposit each round).
4. Review any **creation fee** in ETH (owner-configured; may be zero; capped at 0.001 ETH).
5. Confirm create — your pledge locks and the pool stays **pending** until full.

## Steps — join

1. Browse **Open** pools (or similar matches from create).
2. Confirm the per-round amount and size match what you want.
3. Join — your pledge locks like the creator’s.
4. When the last seat fills, the pool **starts automatically**.

## What the protocol does

Create and join move the required vault shares from free to locked for that pool. When the roster is full, the contract starts the circle: it normalizes pre-start yield back to free shares, shuffles the recipient roster with beacon randomness, mints soulbound membership receipts, and opens round one. Payout order is **not** join order.

## Pending, stale, and leave

| State | What you can do |
| ----- | --------------- |
| Pending | Others can still join; your pledge stays locked |
| Stale | Fill window expired (default 7 days; owner may set 3–7 for new pools); **no new joins**; each member may **leave** and unlock their pledge |
| Active | Started — you cannot leave; you stay for the full circle |

Leave is available after the pool becomes **stale** (still not started). After start, you stay for all rounds.

## Common mistakes

- Underfunding the pledge (remember the 0.05% penalty headroom).
- Assuming you can change size or per-round amount after create — they are fixed.
- Waiting forever on a pool that went **stale** — leave to reclaim collateral.
- Confusing creation fee (ETH to the protocol owner) with miss penalties (those stay in the pool).

## See also

- [Collateral](/user/collateral)
- [Rounds](/user/rounds)
- [Misses and stale pools](/user/misses-and-stale)
- Implementation: [Pledge and join](/guide/pledge-and-join), [Start and shuffle](/guide/start-and-shuffle)
