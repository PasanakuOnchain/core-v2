# 10. Limitations

Honest boundaries of the core-v2 deployment help integrators and participants set correct expectations.

## Scope limits

### Four assets per deployment

The constructor accepts exactly four ERC20 addresses. Which tokens (USDC, USDT, WETH, DAI, etc.) depends on deploy configuration — see `script/deploy.py` env vars.

### No lending or yield

Assets remain on the Pasanaku contract as collateral or escrow. No Aave, Compound, or similar integrations.

### Fixed pool geometry

- Exactly **10** participants and **10** rounds.
- Per-round **amount** is fixed at pool creation.
- **40-day** deposit windows — not calendar months.

### Pull payout UX

Recipients must call `claim_round_payout` after each tick. Wallets and apps must prompt claims; principal does not auto-transfer.

### Stale pending pools

Unfilled pools require individual `leave_pasanaku` calls after stale time. There is no global “cancel pool” admin action.

### No pause or upgrade

Deployed instances cannot be paused, upgraded, or emergency-settled by admin. Bugs or griefing have no onchain circuit breaker.

## Integrator responsibilities

1. Read `supported_assets()` from the target deployment — do not hardcode token addresses across chains.
2. Scale UI with token `decimals()`; onchain `amount` is always raw units.
3. Verify `free_collateral >= pledge(amount)` before create/join flows.
4. Track `pasanaku.index` for current recipient; disable deposit UI for recipients.
5. Surface `updated + 40 days` for tick eligibility.
6. After tick, guide recipient to `claim_round_payout`.
7. Use `token_id` as primary key — do not assume one active pool per asset.
8. Distinguish **pending / stale / ongoing / ended** via `pasanaku()` and `uri()`.
9. Never imply NAKU governance or tradable NFTs without “not deployed” labels.

## When not to use Pasanaku

- Groups smaller or larger than ten without a new contract version.
- Exotic ERC20 tokens (fee-on-transfer, rebasing).
- Use cases requiring instant push payouts without a claim step.
- Environments requiring admin pause or upgradeability on the same address.

---

> **Implemented today**
>
> All limitations above reflect core-v2 as shipped. Integrator checklist: [README.md](../../README.md) — Integrator / indexer playbook.
