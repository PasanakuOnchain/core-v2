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
   distributable pool yield starts at this point.
4. During each 40-day round, every participant except the current recipient
   deposits exactly `round_assets`.
5. Anyone may call `tick` after the round deadline. The recipient then pulls
   the accrued payout through `claim_round_payout`.
6. The final tick returns principal shares, covers principal shortfalls from
   the pool reserve, and divides all remaining yield and reserve shares equally
   among participants.

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
or when a missed round contribution is slashed.

## Pledge and misses

For `N` equal to `6` or `12`:

```text
principal = round_assets * N
penalty_headroom = principal * 5 / 10_000
pledge = principal + penalty_headroom
```

If an obligor misses a round:

1. `round_assets` is withdrawn from that participant's locked vault shares so
   the recipient still receives the full `(N - 1) * round_assets` payout.
2. Shares worth `round_assets * 5 / 10_000` move from the participant's locked
   balance to the pool reserve.
3. No miss penalty is sent to the contract owner.

Round contributions remain liquid ERC-20 escrow. `tick` moves their accounting
from `pool_escrow` to `pending_payout`; the recipient claims later.

## Vault yield and losses

- Yield before pool start remains with the depositor.
- Yield after start is pooled and divided equally at completion.
- Reserve shares first cover participant principal shortfalls caused by vault
  loss or rounding.
- If the reserve cannot cover the full shortfall, the available reserve is
  allocated proportionally and settlement still completes.
- Any reserve remainder joins vault yield in the equal participant split.

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
- `deposit_to_pasanaku(amount, token_id)`
- `tick(token_id)`
- `claim_round_payout(token_id, round_idx)`
- `pasanaku(token_id)`
- `pledge(round_assets, participant_count)`

### Deployment and administration

The constructor is:

```text
Pasanaku(asset, vault, creation_fee_wei)
```

It verifies that `vault.asset()` matches `asset`. The owner may set:

- Creation fee: `set_fee`, capped at `0.001 ETH`.
- Pending-pool stale time: `set_stale_time`, from 3 to 7 days.

`collect_fees` transfers accumulated native creation fees to `owner()`.
It never transfers ERC-20 reserve shares.

Production deployment uses:

```text
PASANAKU_ASSET
PASANAKU_VAULT
PASANAKU_CREATE_FEE_WEI  # optional, defaults to 0
```

## Development

Requirements: Python 3.12+, `uv`, Moccasin, Titanoboa, and Vyper 0.4.3.

```bash
uv sync
uv run mox compile
uv run python -m pytest -q
```

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
docs/erc4626-collateral-accounting-discussion.md
CONTEXT.md
```
