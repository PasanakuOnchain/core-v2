# Collateral

Supply and withdraw the asset that backs your pledge in a pasanaku.

## Goal

Hold enough **free** collateral to create or join, and know what you can withdraw while locked in a pool.

## Steps

1. Open **Collateral** in the app (or follow the prompt from create/join).
2. **Supply** — approve the asset if needed, then deposit. The contract places it in the ERC-4626 vault and credits you with shares.
3. Check balances: total, **in use** (locked in pools), and **free** (available to pledge or withdraw).
4. **Withdraw** only from free collateral — locked shares stay until the pool ends or you leave a pending/stale pool.

## What the protocol does

You do not hold vault shares in your wallet through this path. The Pasanaku contract owns the vault shares and tracks how many are free, locked to a pool, or held in a pool reserve. Supply moves underlying into the vault; withdraw burns free shares for underlying assets.

## Free vs locked

| Kind | You can | Used for |
| ---- | ------- | -------- |
| Free | Withdraw or pledge | Create, join, top-ups |
| Locked | Not withdraw until unlock | Pledge in a pending or active pool |
| Reserve | Not yours personally | Pool penalties / shortfall cover |

When you create or join, the protocol locks a **pledge**: principal equal to `per-round amount × participant count`, plus **1%** headroom for a miss penalty.

Example (six-participant circle, 100 USDC per round):

```text
principal = 100 × 6 = 600 USDC
penalty headroom = 600 × 1% = 6 USDC
pledge ≈ 606 USDC of vault share value
```

## Statuses / outcomes

| Action | Outcome |
| ------ | ------- |
| Supply | Free collateral increases |
| Create / join | Free → locked for that pool |
| Leave after stale | Locked → free again |
| Pool ends | Locked principal returned (subject to settlement); free again |

## Common mistakes

- Creating or joining when free collateral is below the pledge — the transaction reverts.
- Trying to withdraw the full balance while shares are locked in an active pool.
- Ignoring vault risk — share value can fall; see [Risks and fees](/user/risks-and-fees).

## See also

- [Create and join](/user/create-and-join)
- [Misses and stale pools](/user/misses-and-stale)
- Implementation: [Collateral shares](/guide/collateral), [Pledge and join](/guide/pledge-and-join)
