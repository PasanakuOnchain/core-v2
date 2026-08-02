# Misses and stale pools

What happens if someone skips a round deposit, or a pool never fills.

## Goal

Know how misses are covered, where penalties go, and how to exit an unfilled pool.

## Missed round deposit

### Goal

Keep the recipient whole when an obligor does not deposit before tick.

### What the protocol does

If an obligor misses:

1. The contract uses their **locked collateral** to cover the owed per-round amount plus a **1%** penalty.
2. Recovered assets go toward that round’s pot (via pool escrow).
3. Penalty shares move into the **pool reserve** — not to the protocol owner.
4. If locked shares cannot cover the full amount (**underwater** miss), remaining shares are redeemed into escrow, that member’s lock is cleared, and the round pot may be **smaller** than a full `(N − 1) × per-round` payout.

Honest participation is cheaper than missing: you still lose the obligation from collateral and pay the penalty into the reserve.

### Outcomes

| Case | Recipient pot | Misser |
| ---- | ------------- | ------ |
| Solvent miss | Full (from deposits + collateral recovery) | Obligation covered; 1% to pool reserve |
| Underwater miss | May be reduced | Lock cleared after partial recovery |

## Stale unfilled pools

### Goal

Recover collateral if the roster never fills.

### Steps

1. A pending pool snapshots a **stale time** at create (default 7 days; owner may set 3–7 days for new pools).
2. After `created + stale time`, the pool is **stale**: new joins revert.
3. Each member can **leave** individually — locked pledge returns to free collateral.

### Statuses

| Status | Joins | Leave |
| ------ | ----- | ----- |
| Pending (not yet stale) | Allowed until full | No — wait for fill or stale |
| Stale | Blocked | Yes — reclaim pledge |
| Active | N/A | Not via leave |

## Common mistakes

- Ignoring a miss — your collateral still pays; the reserve takes the penalty.
- Leaving funds in a stale pool forever — leave to unlock free collateral.
- Confusing miss penalties (pool reserve) with protocol yield or creation fees (owner).

## See also

- [Collateral](/user/collateral)
- [Create and join](/user/create-and-join)
- [Rounds](/user/rounds)
- Implementation: [Miss and reserve](/guide/miss-and-reserve)
