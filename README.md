# Pasanaku

Onchain rotating savings pools with collateral-backed round obligations. Each pool has nine participants, nine payout rounds, and permissionless settlement after each 40-day deposit window.

**Source of truth:** `src/Pasanaku.vy` and tests. If prose here disagrees with the contract, the contract wins.

## What it does

A **pasanaku** is a fixed-membership pool over one supported ERC20:

1. Participants pre-fund **collateral** per asset, then **create** or **join** a pool with a chosen per-round **amount** (raw token units, e.g. `100 * 10**6` for 100 USDC with 6 decimals).
2. When the ninth member joins, the pool **starts** automatically. Membership is fixed; the ERC1155 receipt is a non-transferable membership record.
3. For each round index `k` (0 … 8), one **recipient** receives principal from the other eight **obligors**. Obligors deposit exactly `amount` during the window; the recipient does not deposit that round.
4. After `updated + 40 days`, anyone may call **`tick`** to settle the round, advance the index, and pay the recipient.
5. After nine ticks, the pool **ends** and pledged collateral unlocks (minus any amounts already slashed during the pool).

Round deposits sit in contract escrow until tick pays the recipient. There is no external lending integration.

## Economics (formula-first)

Constants from the contract: `N = 9`, `MISS_PENALTY_BPS = 5` (0.05% of `amount` per missed obligor deposit).

| Quantity | Formula | Meaning |
|----------|---------|---------|
| Per-round obligor deposit | `amount` | Exact ERC20 units each non-recipient must transfer for the current round |
| Recipient payout (successful tick) | `(N - 1) * amount` | Eight obligor principals, from escrow and/or slash |
| Collateral lock per pool | `pledge(amount) = amount * N + amount * N * MISS_PENALTY_BPS / 10000` | Locked on create/join; released after pool ends |
| Miss penalty per obligor | `amount * MISS_PENALTY_BPS / 10000` | Taken from collateral if deposit missing at tick; sent to `owner()` treasury |

**Example** (6-decimal USDC, `amount = 100_000_000` = 100 USDC):

- Each obligor deposits `100` USDC per round when current.
- Recipient receives `8 * 100 = 800` USDC principal on a fully funded round.
- `pledge(100 USDC) = 900 USDC + 0.45 USDC` penalty reserve (900 principal + 0.05% × 900 penalty headroom).
- One missed deposit at tick: recipient still gets `amount` principal from that obligor’s slash; `0.05 USDC` penalty goes to treasury.

Penalties do not reduce the recipient’s principal target for that round; they are an extra sink on top of obligor collateral.

## Round timing

- Each round has a **40-day deposit window** starting from the pool’s last `updated` timestamp (start time on round 0).
- Obligors may `deposit_to_pasanaku` any time before tick, while the pool is active and they are not the current recipient.
- **`tick` is permissionless** once `block.timestamp >= updated + 40 days`. No admin must advance rounds.

## Collateral and withdrawals

- **`add_collateral`**: increase per-asset balance held by the contract.
- **`withdraw_collateral`**: only **free collateral** — `collateral - collateral_in_use` — is withdrawable while obligations are active.
- Create/join increases `collateral_in_use` by `pledge(amount)` for that pool’s asset.

## Active pools per asset

`active_pasanaku_for_asset(asset)` is a **counter** of started, not-yet-ended pools for that asset. The contract does **not** enforce a single active pool per asset; multiple concurrent active pools for the same ERC20 are possible today. Pending (not started) pools may also coexist.

Integrators should not assume “one pool per token” unless a future version adds enforcement.

## Supported assets and deployment

- Constructor takes **four** ERC20 addresses (`supported_assets()`). Which tokens they are is **deployment-specific** (see `script/deploy.py` env vars).
- **Standard ERC20 only**: no fee-on-transfer, no rebasing; balances must match `transfer` / `transferFrom` amounts.
- Deployed instances are **non-upgradeable**. There is **no pause**, force-settle, or emergency override.

### Owner role

`owner()` (two-step ownable) receives **miss penalties** only. Participants still rely on collateral and permissionless `tick` for round settlement; the owner is not a round operator.

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

Key invariants to preserve when changing code:

- `pledge(amount)` matches `_pledge` / `pledge()` view.
- Successful tick pays recipient `(N - 1) * amount` in principal units.
- Missed obligor: slash `amount + penalty_per`, penalties sum to treasury, recipient still credited `amount` for that obligor.
- Only free collateral is withdrawable while `collateral_in_use > 0`.
- `active_pasanaku_for_asset` increments on start, decrements on end; no hard cap at 1.

```bash
mox test
mox test --coverage
mox test tests/test_pasanaku.py -k tick
```

Coverage config: `.coveragerc` (boa coverage plugin; omits mocks).

## Integrator / indexer playbook

**Canonical read model** — prefer views over inferring from transfers:

| View | Use |
|------|-----|
| `pasanaku(id)` | Pool state: asset, amount, participants, index, started/updated/ended |
| `deposited_for_pasanaku(id, index, participant)` | Round deposit flags |
| `collateral` / `free_collateral` / `collateral_in_use` | Participant balances |
| `pledge(amount)` | Required lock for a given per-round amount |
| `active_pasanaku_for_asset(asset)` | Active pool count (not a uniqueness guarantee) |
| `successful_obligated_deposits` | Historical deposit count per participant |

**Lifecycle events** (index for state changes):

- `PasanakuCreated`, `PasanakuJoined`, `PasanakuStarted`
- `PasanakuDeposited` (per-round obligor payment)
- `PasanakuTicked`, `PasanakuPenalties`, `PasanakuEnded`
- `CollateralAdded`, `CollateralWithdrawn`

**Integration checklist**

1. Read `supported_assets()` from the deployment you target.
2. Scale UI amounts with token `decimals()`; onchain `amount` is always raw units.
3. Before create/join, ensure `free_collateral >= pledge(amount)`.
4. Track `pasanaku.index` for current recipient; disable deposit UI for recipient and after `deposited_for_pasanaku`.
5. Surface `updated + 40 days` for tick eligibility; call or relay `tick` permissionlessly.
6. Do not assume one active pool per asset; use `token_id` as the primary key.

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

### Repo layout

```
src/Pasanaku.vy      # Core protocol
script/deploy.py     # Mainnet-style asset env deploy
script/deploy_mocks.py
tests/               # Titanoboa pytest suite
CONTEXT.md           # Domain glossary for agents (/grill-with-docs)
docs/adr/            # Architecture decision records
```

### Contributing

- Match existing Vyper style and dev revert strings (`dev: ...`).
- Update `CONTEXT.md` when introducing new domain terms.
- Record hard-to-reverse trade-offs in `docs/adr/` (see `docs/adr/README.md`).
- Run `mox test` before opening a PR.

Agent-oriented terminology: **`CONTEXT.md`**. Human protocol reference: this README + NatSpec on `Pasanaku.vy`.
