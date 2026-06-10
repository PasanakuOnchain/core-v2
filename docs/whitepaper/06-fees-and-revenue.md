# 06. Fees and revenue

Pasanaku has two revenue streams in core-v2, both flowing to `owner()` today.

## Creation fee (ETH)

| Property | Value |
|----------|-------|
| Charged on | `create_pasanaku` only |
| Token | Native ETH (`msg.value`) |
| Range | 0 to 0.001 ETH |
| Default at deploy | 0 |
| Admin | `set_fee(fee)` — owner only |
| Collection | `collect_fees()` — sweeps contract ETH balance to `owner()` |

The creation fee is independent of the pool’s ERC20 `amount` and collateral. Joiners do not pay ETH.

## Miss penalty (ERC20)

When an obligor misses a deposit at tick:

```
penalty = amount × MISS_PENALTY_BPS / 10000   // 5 bps
```

Penalties aggregate per tick and transfer to `owner()` via `_distribute_penalties`. Logged in `PasanakuPenalties`.

Miss penalties are **not** taken from recipient principal — they are an additional sink on top of obligor collateral.

## Revenue summary (deployed)

| Source | Asset | Recipient |
|--------|-------|-----------|
| Pool creation | ETH | `owner()` via `collect_fees()` |
| Missed deposits | Pool ERC20 | `owner()` on tick |

## Vision sidebar — not deployed

> **Planned (NAKU governance — not in core-v2)**
>
> A future protocol version may introduce a **NAKU** governance token where stakers vote on proposals and receive a share of protocol fees. That model would replace or supplement the simple `owner()` treasury. See [09 — Protocol vision](09-protocol-vision.md).
>
> Do **not** describe token-holder fee distribution as live behavior for current deployments.

---

> **Implemented today**
>
> ETH fee and ERC20 penalties to `owner()` are in `src/Pasanaku.vy`. See [README.md](../../README.md) — Pool creation fee (ETH) and Owner role.
