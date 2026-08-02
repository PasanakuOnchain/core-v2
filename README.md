# Pasanaku

Onchain rotating savings pools backed by yield-bearing ERC-4626 collateral.
Each deployed `Pasanaku` contract supports one immutable ERC-20 asset and one
vault. The creator chooses a six- or twelve-participant pool.

`src/Pasanaku.vy` and its tests are the source of truth.

## Lifecycle

1. A participant deposits the configured asset through `deposit`. The
   Pasanaku contract deposits those assets in the configured vault and credits
   the participant with vault shares.
2. The creator calls `create_pasanaku(round_assets, participant_count)`, where
   `participant_count` must be `6` or `12`. Joining locks enough shares to back
   `pledge(round_assets, participant_count)`.
3. The pool starts automatically when it reaches its configured size.
   Pre-start vault appreciation is returned to each depositor's free shares;
   the recipient roster is shuffled; distributable pool yield starts at this
   point.
4. During each round, every participant except the current recipient deposits
   exactly `round_assets`.
5. Anyone may call `tick` after the 28-day minimum interval since the last
   successful tick (or pool start). The recipient then pulls the accrued
   payout through `claim_round_payout`.
6. The final tick returns principal shares, covers principal shortfalls from
   the pool reserve, redeems the yield fee directly to the owner, and
   distributes the remaining yield by shuffled participant position.

ERC-1155 membership receipts mint when the pool starts. They are soulbound:
all transfer and approval functions revert.

## Share accounting

Vault shares are the canonical collateral unit:

- `free_shares(participant)` — withdrawable shares.
- `locked_shares(token_id, participant)` — shares assigned to one pool.
- `locked_asset_basis(token_id, participant)` — fixed asset principal used to
  distinguish principal from yield; it is not a second balance.
- `pool_reserve_shares(token_id)` — penalty shares reserved for shortfall
  coverage and final distribution.

The contract owns all ERC-4626 shares. Locking and unlocking only move shares
between internal accounting buckets.

Assets cross the vault boundary only when a user deposits, withdraws, redeems,
when a missed round contribution is slashed, or when the final tick pays the
owner's yield fee.

## Pledge and misses

For `N` equal to `6` or `12`:

```text
principal = round_assets * N
penalty_headroom = principal * 5 / 10_000
pledge = principal + penalty_headroom
```

If an obligor misses a round:

1. Principal plus penalty is priced with one vault preview to keep share
   rounding aligned.
2. If collateral is sufficient, `round_assets` is withdrawn and the penalty
   shares move to the pool reserve.
3. If collateral is underwater, all remaining locked shares are redeemed; the
   recipient receives that partial recovery and the round still progresses.
4. No miss penalty is sent to the contract owner.

Round contributions remain liquid ERC-20 escrow. `tick` moves their accounting
from `pool_escrow` to `pending_payout`; the recipient claims later.

## Vault yield and losses

- Yield before pool start remains with the depositor.
- Yield after start is pooled. At completion, the yield fee is redeemed
  directly to the owner and the remainder is distributed with weight `i + 1`,
  where `i` is the participant's shuffled recipient position.
- Reserve shares first cover participant principal shortfalls caused by vault
  loss or rounding.
- If the reserve cannot cover the full shortfall, the available reserve is
  allocated proportionally and settlement still completes.
- Mid-round vault loss also settles without freezing `tick`; an underwater
  misser can reduce that round's payout to the assets actually recovered.
- Any reserve remainder joins vault yield before the fee and weighted
  participant distribution.

For `N` participants, `total_weight = N * (N + 1) // 2`. Participant `i`
receives `distributable_yield * (i + 1) // total_weight`; integer dust is
included in the final participant's distribution.

Integrators must evaluate the configured vault independently. This contract
does not pause, upgrade, or guarantee against vault insolvency.

## Main interface

### Collateral

- `deposit(assets, receiver) -> shares`
- `withdraw(assets, receiver) -> shares`
- `redeem(shares, receiver) -> assets`
- `free_shares(participant)`
- `locked_shares(token_id, participant)`

### Pools

- `create_pasanaku(round_assets, participant_count)`
- `join_pasanaku(token_id)`
- `leave_pasanaku(token_id)`
- `deposit_to_pasanaku(amount, token_id, participant)`
- `tick(token_id)`
- `claim_round_payout(token_id, round_idx)`
- `pasanaku(token_id)`
- `pledge(round_assets, participant_count)`

### Deployment and administration

The constructor is:

```text
Pasanaku(asset, vault, creation_fee_wei, yield_fee_bps)
```

It verifies that `vault.asset()` matches `asset`. The owner may set:

- Creation fee: `set_fee`, capped at `0.001 ETH`.
- Yield fee: `set_yield_fee`, capped at `505` bps.
- Pending-pool stale time for future pools: `set_stale_time`, from 3 to 7 days.
  Each pool snapshots the value at creation and rejects new joins once stale.

`collect_fees` transfers accumulated native creation fees to `owner()`.
It never transfers ERC-20 reserve shares.

Production deployment targets Base (`networks.base` in
[`moccasin.toml`](moccasin.toml), chain id `8453`) and uses:

```text
PASANAKU_ASSET
PASANAKU_VAULT
PASANAKU_CREATE_FEE_WEI  # optional, defaults to 0
PASANAKU_YIELD_FEE_BPS   # optional, defaults to 0
```

```bash
uv run mox run deploy --network base
```

## Development

Requirements: Python 3.12+, `uv`, Moccasin, Titanoboa, and Vyper 0.4.3.
Copy [`.env.example`](.env.example) to `.env` and set `ALCHEMY_API_KEY`
(and optionally `BLOCKSCOUT_API_KEY` for explorer verify). Moccasin is
configured for Base (`networks.base` / `networks.base-fork`, chain id
`8453`).

```bash
uv sync
uv run mox compile
uv run mox test
```

`mox test` runs unitary tests on the local `pyevm` network and skips the
Fluid fUSDC fork suite. Run the fork parity suite through Moccasin's
configured Base fork (`ALCHEMY_API_KEY` in `.env`):

```bash
uv run mox test tests/fork --network base-fork
# or only the fork marker:
uv run mox test -m fork --network base-fork
```

Override the RPC from [`moccasin.toml`](moccasin.toml) when needed:

```bash
uv run mox test tests/fork --network base-fork --url "$BASE_RPC_URL"
```

Plain pytest still works as a fallback (`BASE_RPC_URL` / `FORK_URL`, optional
`FORK_BLOCK`). The suite uses Base USDC at
`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` and Fluid fUSDC at
`0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169`.

Local mocks include an ERC-20 and an exchange-rate-adjustable ERC-4626 vault:

```bash
uv run mox run deploy_mocks
```

Repository layout:

```text
src/Pasanaku.vy
script/deploy.py
script/deploy_mocks.py
tests/mocks/
tests/unitary/
tests/fork/
tests/utils/
moccasin.toml
.env.example
CONTEXT.md
```
