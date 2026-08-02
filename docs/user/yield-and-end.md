# Yield and end

How vault surplus is shared when the circle finishes.

## Goal

Understand when yield starts, how end settlement works, and why later payout positions earn a larger share.

## When yield starts

Pool yield accounting begins when the circle **starts** (roster full), not when you create or join.

- Appreciation on locked shares **before** start is normalized back to your free shares at start.
- After start, appreciation on locked collateral is pooled for end settlement.

## Steps — what happens at the end

1. The **final tick** runs end settlement.
2. Each member’s remaining **principal** collateral is returned as far as the vault and reserve allow.
3. A configured **yield fee** (if any) is taken from surplus and paid to the protocol owner.
4. Remaining surplus is split by **shuffled payout position** with weights `1, 2, …, N`.
5. Your locked shares unlock; the pool is **ended**.

## What the protocol does

Later positions in the shuffled order get larger weights. For six members, weights are 1 through 6 (total 21). If surplus is 21 USDC, position `#1` gets 1, `#4` gets 4, `#6` gets 6 — integers; leftover dust goes to the last participant.

Early recipients get the pot sooner (like receiving cash early) and a smaller yield share. Late recipients finance earlier pots longer and earn more surplus if the vault performed.

## Early vs late (intuition)

| Position | Cash timing | Yield weight |
| -------- | ----------- | ------------ |
| Early (e.g. #1) | Pot sooner | Smaller share of surplus |
| Late (e.g. #N) | Pot later | Larger share of surplus |

Payout order is random at start — you do not choose your weight.

## Estimates

Apps may show **expected** or estimated yield from current vault surplus. Treat those as illustrations. Misses, fees, and vault losses can change the final amount.

## Common mistakes

- Expecting yield from the moment you joined a pending pool.
- Assuming equal yield for every member — weights follow shuffled position.
- Treating on-screen estimates as guaranteed payouts.

## See also

- [Rounds](/user/rounds)
- [Risks and fees](/user/risks-and-fees)
- [Glossary](/user/glossary)
- Implementation: [End settlement](/guide/end-settlement)
