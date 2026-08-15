---
layout: home
hero:
  name: Pasanaku
  text: Docs
  tagline: Onchain rotating savings pools backed by ERC-4626 vault shares.
  actions:
    - theme: brand
      text: User guide
      link: /user/getting-started
    - theme: alt
      text: Implementation
      link: /guide/overview
features:
  - title: Share-denominated collateral
    details: The contract owns vault shares. Free, locked, and reserve buckets are internal accounting—not separate vault positions.
  - title: Fixed membership
    details: Each pool is exactly 3, 6, 9, or 12 participants. Size is chosen at create time and locked at start.
  - title: Pull payouts
    details: tick settles rounds into pending payouts. Recipients claim later; the pool can advance with unclaimed balances.
---

## Who is this for?

| Guide | Read if you… |
| ----- | ------------ |
| [User guide](/user/getting-started) | Join or create pools in the app — collateral, rounds, yield, and risks in plain language. |
| [Implementation guide](/guide/overview) | Integrate or audit the contract — storage, APIs, and settlement mechanics. |

## Source of truth

Canonical behavior lives in [`src/Pasanaku.vy`](https://github.com/PasanakuOnchain/core-v2/blob/main/src/Pasanaku.vy) and the passing test suite. These docs explain that behavior for people and for integrators.

For a short contributor checklist, see `CONTEXT.md` in the repository root. For install, test, and deploy commands, see `README.md`.

## How to read the docs

**As a participant**

1. [Getting started](/user/getting-started) — wallet, network, and the happy path.
2. [What is a pasanaku?](/user/what-is-pasanaku) through [Rounds](/user/rounds) — how a circle works.
3. [Yield and end](/user/yield-and-end), [Misses and stale pools](/user/misses-and-stale), [Risks and fees](/user/risks-and-fees) — outcomes and caveats.

**As an integrator**

1. [Overview](/guide/overview) — vocabulary and lifecycle.
2. [Collateral](/guide/collateral) through [Rounds](/guide/rounds) — the happy path.
3. [Miss and reserve](/guide/miss-and-reserve) and [End settlement](/guide/end-settlement) — failure and finalization.
4. [Membership](/guide/membership), [Admin](/guide/admin), and [Reference](/guide/reference) — receipts, fees, and lookup tables.
