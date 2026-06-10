# 0002. No single active pool cap

- Status: Accepted
- Date: 2026-06-10

## Context

Integrators and early documentation often assumed **at most one active pasanaku pool per ERC20 asset**. The contract exposes `active_pasanaku_for_asset(asset)`, which sounds like a uniqueness guard.

In code, `_active_pasanaku_by_asset` is incremented in `_start_pasanaku` and decremented when a pool ends. It is a **counter**, not an enforcement mechanism — `create_pasanaku` and `join_pasanaku` never assert the counter equals zero.

Multiple pending pools for the same asset were also always allowed.

## Decision

Allow **unbounded concurrent** started, not-yet-ended pools per asset, subject only to participants having sufficient free collateral. Per-pool ERC20 attribution lives in `_pool_escrow[token_id]` so concurrent pools do not share a fungible pot.

Document `active_pasanaku_for_asset` as an informational counter for indexers, not a protocol-wide mutex.

## Consequences

### Positive

- Permissionless pool creation — no global queue or admin slot allocation.
- Same asset can serve multiple independent groups simultaneously.
- Accounting isolation via `pool_escrow` keeps ticks pool-local.

### Negative / risks

- Integrators must key state by `token_id`, not by asset address alone.
- UX may show multiple open USDC pools — product layer must disambiguate.
- Liquidity fragmentation across pools (by design for fixed membership circles).

## Alternatives considered

- **Assert counter ≤ 1 on create/start** — simpler mental model but blocks parallel communities on the same token.
- **Factory with pool registry per asset** — extra contract complexity; deferred.
