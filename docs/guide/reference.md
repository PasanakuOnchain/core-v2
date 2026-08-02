# Reference

Quick lookup for constants, external API, and events. Behavior details live in the earlier chapters; this page is for scanning.

## Constants

| Name | Value | Meaning |
| --- | --- | --- |
| `_MIN_PARTICIPANT_COUNT` | `6` | Allowed pool size |
| `_MAX_PARTICIPANT_COUNT` | `12` | Allowed pool size |
| `_MISS_PENALTY_BPS` | `5` | 0.05% miss penalty |
| `_BPS_PRECISION` | `10_000` | Basis-point denominator |
| `_MIN_TIME_INTERVAL` | `28 days` | Minimum time between ticks |
| `_DAYS_3` / `_DAYS_7` | `3` / `7` days | Stale-time bounds |
| `_MAX_FEE` | `0.001 ETH` | Creation fee cap |
| `_MAX_YIELD_FEE` | `505` | Yield fee cap (bps) |
| `_TOKEN_AMOUNT` | `1` | ERC-1155 amount per member |

## Public API

### Collateral

- `deposit(assets, receiver) -> shares`
- `withdraw(assets, receiver) -> shares`
- `redeem(shares, receiver) -> assets`
- `free_shares(participant)`
- `locked_shares(token_id, participant)`
- `locked_asset_basis(token_id, participant)`
- `pool_reserve_shares(token_id)`

### Pools

- `create_pasanaku(round_assets, participant_count) -> token_id`
- `join_pasanaku(token_id)`
- `leave_pasanaku(token_id)`
- `deposit_to_pasanaku(amount, token_id, participant)`
- `tick(token_id)`
- `claim_round_payout(token_id, round_idx)`
- `pasanaku(token_id) -> Pasanaku`
- `pledge(round_assets, participant_count) -> uint256`
- `pool_escrow(token_id)`
- `pending_payout(token_id, round_idx)`
- `deposited_for_pasanaku(token_id, index, participant)`
- `successful_obligated_deposits(token_id, participant)`
- `active_pasanaku_count()`
- `asset()` / `vault()`

### Admin

- `fee()` / `set_fee(fee_)`
- `yield_fee()` / `set_yield_fee(yield_fee_)`
- `stale_time()` / `set_stale_time(stale_time)`
- `collect_fees()`
- `collect_yield_fees()`
- Ownable 2-step exports: `owner`, `pending_owner`, `transfer_ownership`, `accept_ownership`, `renounce_ownership`

### ERC-1155

- `uri(token_id)`
- `balanceOf(account, id)`
- `balanceOfBatch`, `exists`, `total_supply`, `supportsInterface` (module exports)
- Transfer / approval mutators revert (soulbound)

## Events

| Event | When |
| --- | --- |
| `CollateralDeposited` | Free-share deposit |
| `CollateralWithdrawn` | Exact-asset withdraw |
| `CollateralRedeemed` | Exact-share redeem |
| `PasanakuCreated` | Pool created |
| `PasanakuJoined` | Participant joined |
| `PasanakuLeft` | Stale leave |
| `PasanakuStarted` | Roster locked / rounds begin |
| `PasanakuDeposited` | Round obligation funded |
| `PasanakuTicked` | Round settled, payout accrued |
| `PasanakuReserved` | Miss covered / penalty reserved |
| `PasanakuSurplusDistributed` | End surplus + fee accounting |
| `PasanakuEnded` | Final tick completed |
| `StaleTimeSet` / `FeeSet` / `YieldFeeSet` | Admin updates |
| `FeesCollected` | Native creation fees or redeemed yield-fee assets |

## Deploy and networks

Production deploy uses env vars and Base networking documented in the repository `README.md`:

```text
PASANAKU_ASSET
PASANAKU_VAULT
PASANAKU_CREATE_FEE_WEI   # optional, default 0
PASANAKU_YIELD_FEE_BPS    # optional, default 0
```

```bash
uv run mox run deploy --network base
```

Fork parity tests target Base USDC + Fluid fUSDC through `mox test tests/fork --network base-fork`.

## See also

- Repository `README.md` — tooling
- Repository `CONTEXT.md` — domain wording rules
- Source: `src/Pasanaku.vy`
