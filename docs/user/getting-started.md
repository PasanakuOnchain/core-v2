# Getting started

Get set up to join or create an onchain pasanaku — a fixed circle of six or twelve people who take turns receiving the pot.

## Goal

Connect on Base, hold the deployment’s asset, supply collateral, then create or join a pool.

## What you need

| Requirement | Why |
| ----------- | --- |
| A wallet | Sign deposits, joins, ticks, and claims |
| Base network | Production deployments target Base |
| The configured ERC-20 (often USDC) | Round deposits and collateral use one asset per deployment |
| ETH for gas (and any creation fee) | Transactions and optional native creation fee |

Each deployment binds one asset and one ERC-4626 vault. Pools do not pick a different token.

## Happy path

1. **Connect** your wallet and switch to Base if prompted.
2. **Supply collateral** — deposit the asset so the protocol holds vault shares for you. See [Collateral](/user/collateral).
3. **Create or join** — pick six or twelve participants and a per-round amount, or join an open pool. See [Create and join](/user/create-and-join).
4. **Run rounds** — obligors deposit each round; anyone can tick after at least 28 days; the recipient claims the pot. See [Rounds](/user/rounds).
5. **Settle at the end** — principal returns and vault surplus is shared by payout position. See [Yield and end](/user/yield-and-end).

In the app you will usually see tabs like **Open** (looking for members), **Started** (active rounds), and **Mine** (pools you are in).

## What the protocol does

Pasanaku locks a **pledge** of vault shares when you create or join. When the roster fills, membership locks, payout order is shuffled, and rounds begin. Collateral stays in the vault so the circle can share yield; missed deposits are covered from locked collateral with a small penalty to the pool reserve.

## Statuses at a glance

| Status | Meaning |
| ------ | ------- |
| Pending / Open | Waiting for members; not started |
| Stale | Did not fill in time; members can leave |
| Active / Started | Rounds in progress |
| Ended | All rounds settled; yield distributed |

## Common mistakes

- Trying to create or join without enough **free** collateral for the pledge.
- Expecting to withdraw shares that are **locked** in a pool.
- Waiting to claim a payout before the next tick — unclaimed pots do not block later rounds.
- Assuming the protocol protects you from vault loss — see [Risks and fees](/user/risks-and-fees).

## See also

- [What is a pasanaku?](/user/what-is-pasanaku)
- [Glossary](/user/glossary)
- Implementation: [Overview](/guide/overview)
