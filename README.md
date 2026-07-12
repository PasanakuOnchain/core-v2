# Pasanaku

Onchain rotating savings pools with collateral-backed round obligations. Each pool has ten participants, ten payout rounds, and permissionless settlement after each 40-day deposit window.

**Conceptual overview:** [docs/whitepaper.md](docs/whitepaper.md) · **Documentation hub:** [docs/README.md](docs/README.md)

**Source of truth:** `src/Pasanaku.vy` and tests. If prose here disagrees with the contract, the contract wins.

## What it does

A **pasanaku** is a fixed-membership pool over one supported ERC20:

1. Participants pre-fund **collateral** per asset, then **create** or **join** a pool with a chosen per-round **amount** (raw token units, e.g. `100 * 10**6` for 100 USDC with 6 decimals).
2. When the tenth member joins, the pool **starts** automatically. Membership is fixed; the ERC1155 receipt is a non-transferable membership record (minted without receiver callback, so contract-wallet participants are supported).
3. For each round index `k` (0 … 9), one **recipient** receives principal from the other nine **obligors**. Obligors deposit exactly `amount` during the window; the recipient does not deposit that round.
4. After `updated + 40 days`, anyone may call `**tick`** to settle the round, accrue principal to `pending_payout`, advance the index, and accrue miss penalties to `pending_penalties` (later claimed via `claim_penalties`).
5. After ten ticks, the pool **ends** and pledged collateral unlocks (minus any amounts already slashed during the pool).

See [docs/protocol-flow.md](docs/protocol-flow.md) for a visual lifecycle and [docs/README.md](docs/README.md) for the full documentation index.

Round deposits sit in per-pool escrow (`pool_escrow`) until tick accrues payout; the recipient claims via `claim_round_payout`. Miss penalties accrue on tick and are pulled via permissionless `claim_penalties`. There is no external lending integration.

## Pool creation fee (ETH)

Creating a pool requires a native ETH fee sent with `create_pasanaku`:

- View current fee: `fee()` (default **0** at deploy).
- Owner sets fee: `set_fee(fee)` — range **0 to 0.001 ETH** (`_MIN_FEE` / `_MAX_FEE`).
- Owner sweeps accumulated ETH: `collect_fees()` — transfers contract ETH balance to `owner()`.
- `join_pasanaku` does **not** require ETH; only create does.

The creation fee is separate from pool collateral (ERC20) and from miss penalties.

## Stale pending pools

A pool that never reaches ten members remains **pending** (`started == 0`). After `created + stale_time`, participants may exit:

- `leave_pasanaku(token_id)` — unlocks that participant’s pledged collateral and removes them from the pool, **preserving relative join order** of remaining members (shift-down, not swap-with-last). Emits `PasanakuLeft`.
- `stale_time` is configurable by owner via `set_stale_time(days)` — **3 to 7 days** (default **7** at deploy).

Integrators should surface stale eligibility and prompt participants to leave or recruit remaining members before the window closes.

## Economics (formula-first)

Constants from the contract: `N = 10`, `MISS_PENALTY_BPS = 5` (0.05% of `amount` per missed obligor deposit).


| Quantity                           | Formula                                                               | Meaning                                                                      |
| ---------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Per-round obligor deposit          | `amount`                                                              | Exact ERC20 units each non-recipient must transfer for the current round     |
| Recipient payout (successful tick) | `(N - 1) * amount`                                                    | Nine obligor principals, from per-pool escrow and/or slash                   |
| Collateral lock per pool           | `pledge(amount) = amount * N + amount * N * MISS_PENALTY_BPS / 10000` | Locked on create/join; released after pool ends                              |
| Miss penalty per obligor           | `amount * MISS_PENALTY_BPS / 10000`                                   | Taken from collateral if deposit missing at tick; accrues to `pending_penalties` until `claim_penalties` |


**Example** (6-decimal USDC, `amount = 100_000_000` = 100 USDC):

- Each obligor deposits `100` USDC per round when current.
- Recipient receives `9 * 100 = 900` USDC principal on a fully funded round.
- `pledge(100 USDC) = 1000 USDC + 0.5 USDC` penalty reserve (1000 principal + 0.05% × 1000 penalty headroom).
- One missed deposit at tick: recipient still gets `amount` principal from that obligor’s slash; `0.05 USDC` penalty accrues for later `claim_penalties`.

Penalties do not reduce the recipient’s principal target for that round; they are an extra sink on top of obligor collateral.

## Round timing

- Each round has a **40-day deposit window** starting from the pool’s last `updated` timestamp (start time on round 0).
- Obligors may `deposit_to_pasanaku` any time before tick, while the pool is active and they are not the current recipient.
- `**tick` is permissionless** once `block.timestamp >= updated + 40 days`. No admin must advance rounds.

## Round payout claim

- `tick` settles the round and **accrues** principal to `pending_payout(token_id, round_idx)`; it does not push-transfer ERC20 to the recipient.
- Only `participants[round_idx]` may call `claim_round_payout(token_id, round_idx)` to receive the accrued amount.
- The pool index advances on `tick` even if the recipient has not claimed yet; unclaimed principal remains in `pending_payout` until claimed.

## Miss penalty claim

- `tick` accrues miss penalties to `pending_penalties(asset)` (logged via `PasanakuPenalties`); it does not ERC20-transfer penalties to `owner()`.
- Anyone may call permissionless `claim_penalties(asset)` to transfer accrued penalties to the current `owner()` (emits `PenaltiesClaimed`).
- View accrued balance with `pending_penalties(asset)`.

## Collateral and withdrawals

- `**add_collateral`**: increase per-asset balance held by the contract.
- `**withdraw_collateral**`: only **free collateral** — `collateral - collateral_in_use` — is withdrawable while obligations are active.
- Create/join increases `collateral_in_use` by `pledge(amount)` for that pool’s asset.

## Active pools per asset

`active_pasanaku_for_asset(asset)` is a **counter** of started, not-yet-ended pools for that asset. The contract does **not** enforce a single active pool per asset; multiple concurrent active pools for the same ERC20 are possible today. Pending (not started) pools may also coexist.

Integrators should not assume “one pool per token” unless a future version adds enforcement. Concurrent active pools for the same asset are safe at the accounting layer: each `token_id` tracks attributable ERC20 in `pool_escrow`, so one pool’s tick cannot spend another pool’s deposits.

## Supported assets and deployment

- Constructor takes **four** ERC20 addresses (`supported_assets()`). Which tokens they are is **deployment-specific** (see `script/deploy.py` env vars).
- **Standard ERC20 only**: no fee-on-transfer, no rebasing; balances must match `transfer` / `transferFrom` amounts.
- Deployed instances are **non-upgradeable**. There is **no pause**, force-settle, or emergency override.

### Owner role

`owner()` (two-step ownable) is the protocol treasury:

- Receives **miss penalties** (ERC20) when anyone calls `claim_penalties(asset)` after tick accrual.
- Receives **creation fees** (ETH) via `collect_fees()`.
- May configure `set_fee` and `set_stale_time`.

The owner does **not** operate rounds — settlement remains permissionless via `tick`. The owner cannot redirect recipient payouts or force-settle pools.

### ERC-1155 membership metadata

Each pool `token_id` maps to a soulbound ERC-1155 receipt (transfers revert). The `uri(token_id)` view returns IPFS metadata reflecting pool state:

| State | Condition |
|-------|-----------|
| **pending** | Created, not started, not yet stale |
| **stale** | Pending and `created + stale_time` elapsed |
| **ongoing** | Started, not ended |
| **ended** | Pool completed after round 9 tick |

Use `uri()` for wallet and explorer display; do not assume tradability.

## Security assumptions and guarantee boundaries

What the protocol is designed to provide:

- **Collateralized obligations**: join/create locks `pledge(amount)`; missed deposits slash `amount + penalty` from collateral while still crediting principal to the recipient payout.
- **Permissionless settlement**: any address may `tick` after the window elapses.
- **Fixed membership after start**: no late joins; ERC1155 transfers are disabled.

What it does **not** claim:

- Not “trustless everywhere”: treasury receives penalties; deployment chooses assets and owner.
- Not safe for arbitrary ERC20s: exotic tokens can break accounting.
- Not protected by admin circuit breakers: bugs or griefing are not pausable onchain.

## Invariant-first testing

Tests use **Titanoboa** + **pytest** via Moccasin (`mox test`). Strategy:

1. **Invariants first** — encode economic rules explicitly (payout size, pledge math, escrow deltas, collateral locks, active counter).
2. **Scenario tests** — full join → deposit → tick → end paths, including multiple active pools per asset (`test_second_active_pasanaku_same_asset_starts`).
3. **Targeted fuzzing** — extend with property tests where high-value; mocks live under `tests/mocks/`.

Tests that assert recipient balance after settlement use the `tick_and_claim` helper in `tests/conftest.py` (tick then `claim_round_payout`).

Key invariants to preserve when changing code:

- `pledge(amount)` matches `_pledge` / `pledge()` view.
- Successful tick accrues `(N - 1) * amount` principal to `pending_payout`; `claim_round_payout` delivers it to the recipient.
- Missed obligor: slash `amount + penalty_per`, penalties accrue to `pending_penalties` (claimable to treasury), recipient still credited `amount` for that obligor.
- Only free collateral is withdrawable while `collateral_in_use > 0`.
- `active_pasanaku_for_asset` increments on start, decrements on end; no hard cap at 1.

```bash
mox test
mox test --coverage
mox test tests/unitary/pasanaku/test_tick_claim.py -k tick
```

Coverage config: `.coveragerc` (boa coverage plugin; omits mocks).

## Integrator / indexer playbook

**Canonical read model** — prefer views over inferring from transfers:


| View                                                   | Use                                                                   |
| ------------------------------------------------------ | --------------------------------------------------------------------- |
| `pasanaku(id)`                                         | Pool state: asset, amount, participants, index, started/updated/ended |
| `deposited_for_pasanaku(id, index, participant)`       | Round deposit flags                                                   |
| `collateral` / `free_collateral` / `collateral_in_use` | Participant balances                                                  |
| `pledge(amount)`                                       | Required lock for a given per-round amount                            |
| `active_pasanaku_for_asset(asset)`                     | Active pool count (not a uniqueness guarantee)                        |
| `successful_obligated_deposits`                        | Historical deposit count per participant                              |
| `pool_escrow(id)`                                      | Per-pool ERC20 attribution ledger                                     |
| `pending_payout(id, round_idx)`                        | Accrued principal awaiting recipient claim                            |
| `pending_penalties(asset)`                             | Accrued miss penalties awaiting `claim_penalties`                     |
| `claim_round_payout(id, round_idx)`                    | Recipient pulls principal after tick (write)                          |
| `claim_penalties(asset)`                               | Permissionless pull of accrued penalties to current `owner()` (write) |
| `fee()`                                                | ETH required on `create_pasanaku` (0–0.001 ETH)                         |
| `uri(id)`                                              | ERC-1155 metadata URI by pool state (pending/stale/ongoing/ended)     |


**Lifecycle events** (index for state changes):

- `PasanakuCreated`, `PasanakuJoined`, `PasanakuLeft`, `PasanakuStarted`
- `PasanakuDeposited` (per-round obligor payment)
- `PasanakuTicked`, `PasanakuPenalties`, `PenaltiesClaimed`, `PasanakuEnded`
- `CollateralAdded`, `CollateralWithdrawn`
- `FeeSet`, `StaleTimeSet`, `FeesCollected`

**Integration checklist**

1. Read `supported_assets()` from the deployment you target.
2. Scale UI amounts with token `decimals()`; onchain `amount` is always raw units.
3. Before create/join, ensure `free_collateral >= pledge(amount)`.
4. Track `pasanaku.index` for current recipient; disable deposit UI for recipient and after `deposited_for_pasanaku`.
5. Surface `updated + 40 days` for tick eligibility; call or relay `tick` permissionlessly.
6. After tick, prompt the round recipient to call `claim_round_payout(token_id, round_idx)` (or relay it).
7. Optionally relay `claim_penalties(asset)` when `pending_penalties(asset) > 0` so treasury receives ERC20.
8. Do not assume one active pool per asset; use `token_id` as the primary key.
9. On create, attach `msg.value >= fee()`; listen for `FeeSet` to update UI.
10. For pending pools, compare `pasanaku(id).created` against stale window (default 7 days; `StaleTimeSet` event); offer `leave_pasanaku` when eligible.

## Development

**Requirements:** Python ≥ 3.12, [Moccasin](https://cyfrin.github.io/moccasin), [uv](https://docs.astral.sh/uv/) (recommended).

```bash
uv sync
mox test
mox test --coverage
```

### Deploy

Production deploy (`script/deploy.py`) expects `.env` (see `moccasin.toml` `dot_env`):

- `PASANAKU_ASSET_USDC`
- `PASANAKU_ASSET_USDT`
- `PASANAKU_ASSET_WETH`
- `PASANAKU_ASSET_DAI`

```bash
# Local pyevm (default)
mox run deploy

# Named network from moccasin.toml
mox run deploy --network sepolia
mox run deploy --network anvil
```

Mock ERC20s for local experiments:

```bash
mox run deploy_mocks
```

## Documentation

| Resource | Audience |
|----------|----------|
| [docs/README.md](docs/README.md) | Documentation hub |
| [docs/whitepaper.md](docs/whitepaper.md) | Public narrative — economics, governance, security |
| [docs/protocol-flow.md](docs/protocol-flow.md) | Contract-centric lifecycle diagram |
| [docs/adr/](docs/adr/) | Architecture decision records |
| [CONTEXT.md](CONTEXT.md) | Domain glossary and wording guardrails |

### Repo layout

```
src/Pasanaku.vy      # Core protocol
script/deploy.py     # Mainnet-style asset env deploy
script/deploy_mocks.py
tests/               # Titanoboa pytest suite
CONTEXT.md           # Domain glossary for agents (/grill-with-docs)
docs/
  README.md          # Documentation hub
  whitepaper.md      # Public-facing whitepaper
  protocol-flow.md   # Lifecycle diagram
  adr/               # Architecture decision records
  whitepaper/        # Extended chapter-by-chapter narrative
```

### Contributing

- Match existing Vyper style and dev revert strings (`dev: ...`).
- Update `CONTEXT.md` when introducing new domain terms.
- Record hard-to-reverse trade-offs in `docs/adr/` (see `docs/adr/README.md`).
- Run `mox test` before opening a PR.

Agent-oriented terminology: `CONTEXT.md`.  
Human protocol reference: this README + NatSpec on `Pasanaku.vy`.