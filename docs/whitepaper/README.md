# Pasanaku whitepaper

A narrative guide to the Pasanaku rotating savings protocol. This document explains *why* and *how* at a product level; precise integrator details live in the root [README.md](../../README.md) and [CONTEXT.md](../../CONTEXT.md).

## Reading order

Read chapters **01–08** and **10** for what is deployed in `core-v2`. Chapter **09** describes the **NAKU governance vision** — it is **not** implemented in the current contract.

1. [01 — Introduction](01-introduction.md)
2. [02 — Design goals](02-design-goals.md)
3. [03 — Architecture](03-architecture.md)
4. [04 — Pool lifecycle](04-pool-lifecycle.md)
5. [05 — Economics](05-economics.md)
6. [06 — Fees and revenue](06-fees-and-revenue.md)
7. [07 — Membership NFT](07-membership-nft.md)
8. [08 — Security](08-security.md)
9. [09 — Protocol vision (NAKU)](09-protocol-vision.md) — *planned, not deployed*
10. [10 — Limitations](10-limitations.md)

## Audience

- **Community and product** — understand the savings-circle model and trust boundaries.
- **Integrators** — use this for context; wire against views and events in the root README.
- **Auditors** — cross-check every claim against `src/Pasanaku.vy`; vision language in chapter 09 is explicitly out of scope for current deployments.

## Related

- [Documentation hub](../README.md)
- [Protocol lifecycle diagram](../protocol-flow.md)
- [Architecture decision records](../adr/)
