---
layout: home
hero:
  name: Pasanaku
  text: Implementation guide
  tagline: Onchain rotating savings pools backed by ERC-4626 vault shares.
  actions:
    - theme: brand
      text: Start with overview
      link: /guide/overview
    - theme: alt
      text: Constants and API
      link: /guide/reference
features:
  - title: Share-denominated collateral
    details: The contract owns vault shares. Free, locked, and reserve buckets are internal accounting—not separate vault positions.
  - title: Fixed membership
    details: Each pool is exactly six or twelve participants. Size is chosen at create time and locked at start.
  - title: Pull payouts
    details: tick settles rounds into pending payouts. Recipients claim later; the pool can advance with unclaimed balances.
---

## Source of truth

Canonical behavior lives in [`src/Pasanaku.vy`](https://github.com/PasanakuOnchain/core-v2/blob/main/src/Pasanaku.vy) and the passing test suite. This guide explains how that implementation works.

For a short contributor checklist, see `CONTEXT.md` in the repository root. For install, test, and deploy commands, see `README.md`.

## How to read this guide

1. [Overview](/guide/overview) — vocabulary and lifecycle.
2. [Collateral](/guide/collateral) through [Rounds](/guide/rounds) — the happy path.
3. [Miss and reserve](/guide/miss-and-reserve) and [End settlement](/guide/end-settlement) — failure and finalization.
4. [Membership](/guide/membership), [Admin](/guide/admin), and [Reference](/guide/reference) — receipts, fees, and lookup tables.
