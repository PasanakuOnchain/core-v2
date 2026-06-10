# Pasanaku documentation

Lightweight index for protocol docs. **Canonical behavior** is always `src/Pasanaku.vy` and passing tests.

## Start here

| Document | Audience |
|----------|----------|
| [whitepaper.md](whitepaper.md) | Concept, economics, governance boundaries — public narrative |
| [protocol-flow.md](protocol-flow.md) | Contract-centric lifecycle diagram (Mermaid) |
| [../README.md](../README.md) | Integrator / developer reference — formulas, views, events, deploy |
| [../CONTEXT.md](../CONTEXT.md) | Terminology and wording guardrails for agents and contributors |

## Architecture decisions

Irreversible or surprising choices are recorded under [adr/](adr/). See [adr/README.md](adr/README.md) for when to write an ADR.

| ADR | Topic |
|-----|-------|
| [0001-pull-claim-payouts.md](adr/0001-pull-claim-payouts.md) | Recipients claim after tick |
| [0002-no-single-active-pool-cap.md](adr/0002-no-single-active-pool-cap.md) | Multiple active pools per asset |
| [0003-stale-pending-exit.md](adr/0003-stale-pending-exit.md) | `leave_pasanaku` for unfilled pools |
| [0004-soulbound-membership-receipt.md](adr/0004-soulbound-membership-receipt.md) | Non-transferable ERC-1155 today |

## Extended whitepaper

Chapter-by-chapter narrative (design goals, limitations, detailed vision): [whitepaper/](whitepaper/).
