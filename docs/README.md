# Pasanaku documentation

Central index for protocol documentation. **Canonical behavior** is always `src/Pasanaku.vy` and passing tests.

## Start here

| Document | Purpose |
|----------|---------|
| [../README.md](../README.md) | Integrator reference — formulas, views, events, testing, deploy |
| [../CONTEXT.md](../CONTEXT.md) | Domain glossary and wording guardrails for agents and contributors |

## Whitepaper

Narrative overview of Pasanaku: problem, design, lifecycle, economics, and future vision. Each chapter ends with an **Implemented today** callout linking back to the contract.

| # | Chapter | Topic |
|---|---------|-------|
| — | [whitepaper/README.md](whitepaper/README.md) | Index and reading order |
| 01 | [Introduction](whitepaper/01-introduction.md) | What Pasanaku is; ROSCA context |
| 02 | [Design goals](whitepaper/02-design-goals.md) | Goals and explicit non-goals |
| 03 | [Architecture](whitepaper/03-architecture.md) | Actors, money flow, single-contract model |
| 04 | [Pool lifecycle](whitepaper/04-pool-lifecycle.md) | Collateral → rounds → end; stale exit |
| 05 | [Economics](whitepaper/05-economics.md) | Pledge, payouts, penalties, worked example |
| 06 | [Fees and revenue](whitepaper/06-fees-and-revenue.md) | ETH creation fee + miss penalties |
| 07 | [Membership NFT](whitepaper/07-membership-nft.md) | Soulbound ERC-1155 today |
| 08 | [Security](whitepaper/08-security.md) | Assumptions, threat model, invariants |
| 09 | [Protocol vision](whitepaper/09-protocol-vision.md) | NAKU governance (**not deployed**) |
| 10 | [Limitations](whitepaper/10-limitations.md) | Scope boundaries and integrator duties |

## Technical reference

| Document | Purpose |
|----------|---------|
| [protocol-flow.md](protocol-flow.md) | Contract-centric Mermaid lifecycle (including stale exit) |
| [adr/README.md](adr/README.md) | When and how to write ADRs |

## Architecture decision records

| ADR | Decision |
|-----|----------|
| [0001-pull-claim-payouts.md](adr/0001-pull-claim-payouts.md) | Recipients claim payouts after tick |
| [0002-no-single-active-pool-cap.md](adr/0002-no-single-active-pool-cap.md) | Multiple concurrent active pools per asset |
| [0003-stale-pending-exit.md](adr/0003-stale-pending-exit.md) | `leave_pasanaku` for unfilled pending pools |

## Audiences

- **Integrators and indexers** — start with the root [README.md](../README.md) and [protocol-flow.md](protocol-flow.md).
- **Product and community readers** — start with [whitepaper/01-introduction.md](whitepaper/01-introduction.md).
- **Contributors changing economics or interfaces** — read relevant ADRs before proposing changes.
