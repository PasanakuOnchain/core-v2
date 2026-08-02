# Rounds

Once started, a pasanaku runs exactly `N` rounds. Round `k` pays shuffled `participants[k]`. Everyone else owes one deposit of `round_assets`.

## Funding: `deposit_to_pasanaku`

```text
deposit_to_pasanaku(amount, token_id, participant)
```

Anyone may fund an obligor's deposit. Assets are pulled from `msg.sender`; credit is recorded for `participant`.

Guards:

- pool started and not ended
- `participant` is in the roster
- `participant` is not the current-round recipient
- participant has not already deposited for this `index`
- `amount == round_assets`

Effects:

- `_deposited_for_pasanaku[token_id][round_idx][participant] = True`
- `_successful_obligated_deposits[token_id][participant] += 1`
- `_pool_escrow[token_id] += amount`

Emits `PasanakuDeposited` with both `account` (obligor) and `payer`.

Contributions stay liquid ERC-20 in escrow. They are not converted to vault shares.

## Time gate: `_MIN_TIME_INTERVAL`

```text
assert pasanaku.updated + _MIN_TIME_INTERVAL <= block.timestamp
```

`_MIN_TIME_INTERVAL` is 28 days. `updated` is set at start and on every successful `tick`. This is a minimum interval between ticks, not a soft calendar hint.

## `tick`

Permissionless. Settles the current round:

1. Require started, not ended, and interval elapsed.
2. `_settle_round` — sum deposits and cover misses from locked collateral (see [Miss and reserve](./miss-and-reserve.md)).
3. `_accrue_recipient_payout` — move `payout` from `_pool_escrow` to `_pending_payout[token_id][round_idx]`.
4. Advance `updated` and `index`.
5. Emit `PasanakuTicked`.
6. On the last round (`round_idx == participant_count - 1`), set `ended`, call `_end_pasanaku`, decrement `_active_pasanaku_count`, emit `PasanakuEnded`.

`tick` does **not** transfer assets to the recipient.

If the vault cannot currently withdraw/redeem the assets needed for a solvent miss conversion, the vault call reverts the whole tick. Callers can retry after liquidity expands; solvent locked collateral is not wiped for a temporary vault limit.

## `claim_round_payout`

```text
claim_round_payout(token_id, round_idx)
```

Only the designated recipient (`participants[round_idx]`) may claim. Clears `_pending_payout` and transfers underlying to the recipient.

The pool may advance while earlier payouts remain unclaimed. Indexers should track pending balances separately from round progress.

## Happy-path payout size

With no misses, tick accrues `(N - 1) * round_assets`. With an underwater misser, the accrued amount is liquid deposits plus whatever assets were recovered from that participant's remaining shares—possibly less than a full round obligation.

## See also

- [Miss and reserve](./miss-and-reserve.md)
- `CONTEXT.md` — Round deposits and pull payouts
- `tests/unitary/pasanaku/test_tick_claim.py`
