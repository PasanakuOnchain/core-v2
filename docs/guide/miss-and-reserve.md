# Miss and reserve

When `tick` finds an obligor who has not deposited for the current round, `_settle_round` covers the obligation from that participant's locked shares and may move a miss penalty into the pool reserve.

The contract owner never receives miss penalties. Penalties stay in `_pool_reserve_shares` for end-of-pool shortfall coverage and leftover surplus distribution.

## Per-misser pricing

For each non-recipient who has not deposited:

```text
amount = round_assets
penalty_assets = amount * _MISS_PENALTY_BPS / 10_000
principal_shares = vault.previewWithdraw(amount)
needed_shares = vault.previewWithdraw(amount + penalty_assets)
recoverable = vault.previewRedeem(locked)   # if locked > 0
```

Using separate previews keeps principal and penalty share rounding aligned with the vault's withdraw path.

## Solvent miss

Condition: locked shares cover principal conversion and `previewRedeem(locked)` can still produce at least `round_assets`.

Then:

1. `vault.withdraw(amount, self, self)` pulls liquid assets into the contract.
2. Penalty shares are derived from `needed_shares - burned_shares`, with a floor from `previewWithdraw(penalty_assets)` when helpful, capped by remaining locked shares.
3. Locked shares decrease by burned + penalty shares.
4. Asset basis decreases by `amount + penalty_assets` (or clears if locked hits zero).
5. Penalty shares credit `_pool_reserve_shares[token_id]`.
6. `funded_assets = amount` adds to escrow and the recipient payout total.

Emits `PasanakuReserved` with `assets = penalty_assets` (economic penalty) and `shares = penalty_shares`.

## Underwater miss

Condition: locked shares cannot cover the principal preview, or redeeming all locked shares would not recover `round_assets`.

Then:

1. Redeem **all** remaining locked shares to the contract (`vault.redeem(locked, self, self)`), or skip if already zero.
2. Clear the participant's locked shares and asset basis.
3. `funded_assets` equals whatever the redeem returned (possibly partial).
4. No new reserve shares are taken from an empty position.

Tick still progresses. The round payout becomes liquid deposits from other obligors plus this partial recovery—strictly less than a full `(N - 1) * round_assets` when recovery is incomplete.

## Escrow handoff

After all obligors are processed, `_settle_round` returns `recipient_payout`. `_accrue_recipient_payout` asserts escrow coverage and moves that amount into `_pending_payout`.

## Vault liquidity reverts

If a solvent path's `withdraw` / `redeem` fails because the vault cannot pay out now, the entire `tick` reverts. That is intentional: temporary vault liquidity limits should not confiscate solvent collateral. Retry when the vault can serve the conversion.

## See also

- [End settlement](./end-settlement.md)
- `CONTEXT.md` — Miss and pool reserve
- `tests/unitary/pasanaku/test_tick_claim.py`, `test_fees.py`
