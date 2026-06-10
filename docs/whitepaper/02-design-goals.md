# 02. Design goals

## Goals

### Collateral-backed round obligations

Every participant locks `pledge(amount)` on create or join. That pledge covers the full principal path (`amount × N`) plus a penalty reserve (`amount × N × 5 / 10000`). Obligors who miss a deposit lose principal and penalty from collateral; the recipient still receives principal credit for that round.

### Permissionless settlement

After each 40-day deposit window, **any address** may call `tick`. No admin, keeper, or owner must advance rounds. This keeps liveness independent of any single operator.

### Fixed membership after start

Ten participants join before the pool starts. The tenth join triggers `_start_pasanaku`, mints ERC-1155 membership receipts, and fixes the participant list. No mid-pool joins or transfers.

### Per-pool accounting for concurrent pools

Each `token_id` maintains its own `pool_escrow` ledger. Multiple active pools for the same ERC20 can run in parallel without cross-pool balance leakage.

### Minimal token assumptions

Supported assets are four deployment-configured **standard ERC20** addresses. Fee-on-transfer, rebasing, and donation-style tokens are out of scope.

## Explicit non-goals

| Non-goal | Rationale |
|----------|-----------|
| **Pause or emergency override** | Instances are non-upgradeable; no admin circuit breaker |
| **Upgradeability** | Deploy new instance for new behavior |
| **Exotic ERC20 support** | Internal balances must match transfer amounts |
| **Automatic push payouts** | Recipients pull via `claim_round_payout` (see ADR-0001) |
| **Single active pool per asset** | Counter only; no uniqueness enforcement (see ADR-0002) |
| **Onchain governance in core-v2** | Ownable admin today; NAKU vision is separate (chapter 09) |

---

> **Implemented today**
>
> All goals and non-goals above reflect `src/Pasanaku.vy`. See [README.md](../../README.md) — Security assumptions and Active pools per asset.
