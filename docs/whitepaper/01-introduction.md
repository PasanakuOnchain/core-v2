# 01. Introduction

Pasanaku brings a centuries-old savings practice onchain: the **rotating savings and credit association** (ROSCA), also known as a **tanda**, **susu**, **chit fund**, or **pasanaku** in Latin American communities.

In a traditional ROSCA, a fixed group agrees on a contribution amount and schedule. Each period, every member pays in; one member receives the collected pot. Over time, each member receives exactly one payout. Trust is social — if someone stops paying, the circle breaks.

Pasanaku replaces that social trust layer with **collateral-backed obligations on Ethereum**. Participants lock enough collateral to cover all ten round payments plus a small penalty reserve before joining. Round settlement is **permissionless** after each 40-day window. A single defaulter cannot block payouts for the other nine members.

## What makes it onchain

- **Fixed membership** — ten participants, ten rounds, one supported ERC20 per pool.
- **Collateral first** — join only after `pledge(amount)` is locked; missed deposits slash collateral while still crediting the recipient.
- **No central round operator** — anyone may call `tick` once the deposit window elapses.
- **Pull payouts** — recipients claim principal after settlement (`claim_round_payout`).

Participants lock `pledge(amount)` before joining — enough collateral to cover all ten round obligations plus a small penalty reserve, so one defaulter cannot halt payouts for others.

## What Pasanaku is not

- Not a lending protocol — no yield, no liquidity pools, no credit scoring.
- Not a fiat bridge — assets are standard ERC20 tokens only.
- Not upgradeable or pausable on deployed instances — behavior is fixed at deploy time.

---

> **Implemented today**
>
> Core-v2 implements N=10 pools, 40-day rounds, collateral locks, permissionless tick, and soulbound ERC-1155 membership receipts. See [README.md](../../README.md) and `src/Pasanaku.vy`.
