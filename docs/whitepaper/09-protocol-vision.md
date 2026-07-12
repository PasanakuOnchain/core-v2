# 09. Protocol vision (NAKU)

> **This chapter describes planned future governance. It is NOT deployed in core-v2.**

The current Pasanaku contract uses **Ownable two-step admin**: a single `owner()` receives ETH creation fees via `collect_fees()` and ERC20 miss penalties via permissionless `claim_penalties` (accrued on tick into `pending_penalties`). There is no governance token, no staking, and no onchain proposal system in `src/Pasanaku.vy`.

## Intended direction

The long-term vision introduces **NAKU**, a governance token that would:

1. **Govern protocol parameters** — fee levels, stale windows, supported assets on new deployments, and treasury policy via onchain proposals and voting.
2. **Align stakeholders with revenue** — stakers who vote (or lock NAKU) receive a share of protocol fees collected from creation fees and miss penalties.
3. **Decentralize treasury** — migrate from a single `owner()` EOA or multisig to token-holder-directed disbursement.

## Relationship to core-v2

| Aspect | core-v2 (today) | Vision (NAKU) |
|--------|-----------------|---------------|
| Fee recipient | `owner()` | Stakers / treasury governed by votes |
| Admin functions | `set_fee`, `set_stale_time`, `collect_fees` | Proposal + timelock execution |
| Membership NFT | Soulbound ERC-1155 | Possible tradability — separate decision |
| Deployment | Fixed non-upgradeable instance | Likely new deployment or explicit migration |

Core-v2 is designed as a **minimal, auditable base layer**. Governance would sit in a future version or companion contracts — not as an implied feature of current deployments.

## Migration considerations (conceptual)

Any move from Ownable to NAKU governance would require explicit community process:

- Snapshot of existing `owner()` treasury and fee policy
- Deployment of governance contracts with clear upgrade/migration path
- Communication that legacy instances remain fixed unless users opt in to a new deployment

None of this exists onchain in core-v2 today.

## Documentation guardrails

When writing about Pasanaku publicly:

- ✅ “Penalties accrue on tick and go to `owner()` via `claim_penalties` in the current deployment.”
- ✅ “NAKU governance and staker fee share are on the roadmap, not live.”
- ❌ “Token holders earn protocol revenue.” (without “planned” qualifier)
- ❌ “Governance votes control fees today.”
- ❌ “Tick pushes miss penalties to `owner()` as an ERC20 transfer.” (accrue then `claim_penalties`)

See also [CONTEXT.md](../../CONTEXT.md) — Protocol vision vs deployed behavior.

---

> **Implemented today**
>
> **Nothing in this chapter is deployed.** Current behavior: Ownable admin and `owner()` treasury only. See [README.md](../../README.md) — Owner role and [06 — Fees and revenue](06-fees-and-revenue.md).
