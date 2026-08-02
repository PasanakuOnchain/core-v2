# Admin and fees

Protocol administration is owner-gated through snekmate two-step ownable. Fee parameters are capped at construction and on every setter.

## Constructor

```text
Pasanaku(asset, vault, creation_fee_wei, yield_fee_bps)
```

Checks:

- non-empty asset and vault
- `vault.asset() == asset`
- `fee_ <= _MAX_FEE` (`0.001 ETH`)
- `yield_fee_ <= _MAX_YIELD_FEE` (`505` bps)

Initializes `_stale_time = 7 days`, stores fees, and boots ownable + ERC-1155 modules. Emits `FeeSet` and `YieldFeeSet`.

## Creation fee

| API | Role |
| --- | --- |
| `fee()` | Current creation fee in wei |
| `set_fee(fee_)` | Owner update, capped by `_MAX_FEE` |
| `create_pasanaku` | Requires `msg.value >= fee`, refunds surplus |
| `collect_fees()` | Sends the contract's full native balance to `owner()` |

`collect_fees` never moves ERC-20 reserve shares or vault shares. Emits `FeesCollected` with the native amount.

## Yield fee

| API | Role |
| --- | --- |
| `yield_fee()` | Current global yield fee bps (future pools snapshot this) |
| `set_yield_fee(yield_fee_)` | Owner update, capped by `_MAX_YIELD_FEE` |
| pool `yield_fee` field | Value snapshotted at `create_pasanaku` |
| `_end_pasanaku` | Accrues `fee_shares` into `_collected_fee_shares` |
| `collect_yield_fees()` | Redeems collected fee shares to the owner via the vault |

Miss-penalty reserve leftovers are not fee-eligible. Only locked shares above remaining asset basis (`yield_surplus`) are charged.

NatSpec on `set_yield_fee` and `_end_pasanaku` is the authoritative description of this split.

## Stale time

| API | Role |
| --- | --- |
| `stale_time()` | Global default for new pools |
| `set_stale_time(stale_time)` | Owner; must be in `[3 days, 7 days]` |

Each pool stores its own `stale_time` at creation. Changing the global value does not rewrite existing pools.

## What the owner cannot do

- Pause the contract or individual pools
- Seize user free/locked shares
- Redirect miss penalties to the owner
- Upgrade the Vyper bytecode
- Change `_ASSET` / `_VAULT` after deploy

Integrators must evaluate vault solvency and liquidity independently.

## See also

- [End settlement](./end-settlement.md)
- Repository `README.md` — deployment env vars
- `tests/unitary/pasanaku/test_admin.py`, `test_fees.py`
