# Pasanaku domain context

Glossary and wording guardrails for agents (`/grill-with-docs`, `/grill-me`) and contributors.

## Contradiction policy

**The deployed contract behavior in `src/Pasanaku.vy` is canonical.**

When README, NatSpec, comments, or chat prose disagree with code:

1. Treat the contract + passing tests as truth.
2. Fix documentation in the same change set when possible.
3. Do not “document aspirational limits” (e.g. one pool per asset) unless enforced in code.

If unsure, read `pledge()`, `_settle_round`, `tick`, and `active_pasanaku_for_asset` before answering.

---

## Glossary

### Pasanaku

**Language:** A fixed-size rotating savings pool instance identified by `token_id`, denominated in one supported ERC20, with ten participants and ten rounds.

**Relationships:** Created via `create_pasanaku`; joined until `N=10`; then `PasanakuStarted`. State in `pasanaku(id)`. ERC1155 `balanceOf` is a membership receipt only.

**Example dialogue:**
- ✅ “Pool `token_id=3` is on round index 2; the recipient is `participants[2]`.”
- ❌ “The pasanaku token is tradable on secondary markets.” (transfers revert)

---

### Participant

**Language:** An address in `pasanaku.participants` for a given pool. Membership is fixed after start.

**Relationships:** Must lock `pledge(amount)` on create/join. May `deposit_to_pasanaku` when not the current recipient. Receives ERC1155 amount 1 at start.

**Example dialogue:**
- ✅ “Alice is participant 0 and was the round-0 recipient.”
- ❌ “A new wallet can join mid-round after start.”

---

### amount (per-round obligor deposit)

**Language:** `pasanaku.amount` — the exact raw ERC20 units each non-recipient must pay each round (`deposit_to_pasanaku` enforces equality).

**Relationships:** Not “total pool size.” Recipient payout per settled round = `(N-1) * amount`. UI must scale by token decimals.

**Example dialogue:**
- ✅ “With `amount = 100e6` USDC, each obligor sends 100 USDC per round.”
- ❌ “Amount is the total 1000 USDC locked upfront.” (that’s `pledge`, not `amount`)

---

### Round / round index

**Language:** Index `k = pasanaku.index` before `tick`. Ten rounds (`0 … 9`). Recipient = `participants[k]`.

**Relationships:** Each round has a 40-day window from `updated`. Tick increments index; when `k == N-1` (9) tick ends the pool.

**Example dialogue:**
- ✅ “Round 4’s recipient is the fifth participant in join order.”
- ❌ “Rounds are calendar months.” (only `40 days` onchain)

---

### Obligor deposit

**Language:** `deposit_to_pasanaku(amount, token_id)` — ERC20 escrow on the contract until tick pays the recipient.

**Relationships:** Tracked in `_deposited_for_pasanaku`. Distinct from collateral (penalty backing).

**Example dialogue:**
- ✅ “Nine of ten obligors deposited; tick will slash the one missing.”
- ❌ “Deposits go to the recipient’s wallet immediately.”

---

### tick

**Language:** Permissionless `tick(token_id)` after `updated + 40 days`. Settles current round, accrues principal to `pending_payout`, routes penalties to owner, advances index or ends pool.

**Relationships:** Emits `PasanakuTicked`; may emit `PasanakuPenalties`. Recipient claims ERC20 via `claim_round_payout`. Not callable by owner exclusively.

**Example dialogue:**
- ✅ “Anyone can tick once the 40-day window elapses.”
- ❌ “The protocol admin must tick each round.”
- ❌ “Tick sends principal directly to the recipient’s wallet.” (recipient must `claim_round_payout`)

---

### Collateral

**Language:** Per-participant per-asset balance `_collateral[account][asset]` held on the Pasanaku contract via `add_collateral`.

**Relationships:** Split into **pledged** (`collateral_in_use`) and **free** (`free_collateral` view). Missed deposits slash collateral.

**Example dialogue:**
- ✅ “Bob’s free USDC collateral is 50e6 after locking pledge for two pools.”
- ❌ “Collateral is the same bucket as round escrow.” (deposits are separate ERC20 balance on contract)

---

### Pledged collateral / pledge(amount)

**Language:** `collateral_in_use` increment on create/join. `pledge(amount) = amount*N + amount*N*MISS_PENALTY_BPS/10000`.

**Relationships:** Released after `PasanakuEnded` via `_unlock_collateral_in_use`, net of slashes recorded in `_slash_from_in_use`.

**Example dialogue:**
- ✅ “Joining requires `free_collateral >= pledge(amount)`.”
- ❌ “Pledge is optional if you promise to deposit.”

---

### Free collateral

**Language:** `collateral - collateral_in_use` when positive; only this portion is withdrawable during active obligations.

**Relationships:** `withdraw_collateral` reverts if amount exceeds free balance.

**Example dialogue:**
- ✅ “You cannot withdraw pledged USDC until the pool ends.”
- ❌ “All collateral is withdrawable anytime.”

---

### Miss penalty

**Language:** `amount * MISS_PENALTY_BPS / 10000` (5 bps = 0.05% of `amount`) per missed obligor deposit, slashed with principal `amount` from collateral.

**Relationships:** Summed to `owner()` on tick (`PasanakuPenalties`). Does not reduce recipient’s `amount` credit for that obligor.

**Example dialogue:**
- ✅ “Penalty is 0.05% of the per-round amount, sent to treasury.”
- ❌ “A miss only costs the penalty, not the round principal.”

---

### Treasury sink

**Language:** `owner()` receives aggregated miss penalties only, not obligor principal.

**Relationships:** Ownable two-step; economically relevant but does not operate rounds.

**Example dialogue:**
- ✅ “Treasury earned 0.4 USDC in penalties this tick.”
- ❌ “Owner can redirect recipient payouts.”

---

### Pending pool

**Language:** `pasanaku.started == 0` — created, accepting joins, not yet ten participants.

**Relationships:** Multiple pending pools per asset allowed. No ERC1155 mint until start.

**Example dialogue:**
- ✅ “Token id 5 is pending with 3/10 participants.”
- ❌ “Pending pool is ‘active’ in `active_pasanaku_for_asset`.” (counter only counts started, unended)

---

### Active pool count

**Language:** `active_pasanaku_for_asset(asset)` — number of started, not-ended pools for that asset.

**Relationships:** Incremented in `_start_pasanaku`, decremented on end. **Not** a cap of 1; multiple concurrent actives are valid today.

**Example dialogue:**
- ✅ “USDC active count is 2 — two running pools.”
- ❌ “Only one USDC pool can run at a time.” (documented old misconception; code does not enforce)

---

### pool_escrow

**Language:** Per-pool ERC20 attribution ledger `_pool_escrow[token_id]`. View: `pool_escrow(token_id)`.

**Relationships:** Credited on `deposit_to_pasanaku` and miss slashes in `_settle_round`; debited on payout accrual and penalty distribution. Isolates concurrent same-asset pools.

**Example dialogue:**
- ✅ “Pool B’s `pool_escrow` is unchanged after pool A ticks.”
- ❌ “All deposits share one fungible pot with no per-pool ledger.”

---

### pending_payout / claim_round_payout

**Language:** `pending_payout(token_id, round_idx)` holds accrued principal after `tick`. `claim_round_payout(token_id, round_idx)` transfers ERC20 to `participants[round_idx]` only.

**Relationships:** Pool advances on `tick` even if claim is delayed. Distinct from collateral and from obligor deposit escrow.

**Example dialogue:**
- ✅ “Recipient called `claim_round_payout(3, 2)` after round 2 ticked.”
- ❌ “Principal arrives in the recipient wallet inside the same `tick` transaction.”

---

## Correct vs incorrect wording

| Topic | ✅ Say | ❌ Avoid |
|-------|--------|----------|
| Decentralization | Permissionless settlement; collateralized obligations | “100% trustless” / “no privileged roles” (owner + treasury exist) |
| amount | Per-round obligor deposit in raw token units | Total savings goal or TVL |
| pledge | `amount*N` plus penalty reserve | Same as single `amount` |
| Payout | `(N-1) * amount` principal to recipient | `N * amount` |
| Payout delivery | Recipient calls `claim_round_payout` after tick | Tick sends ERC20 directly to recipient wallet |
| Penalty | 0.05% of `amount` per miss (5 bps) | 5% penalty |
| Pools per asset | Counter; multiple active allowed | “One active pool per asset” (unless code adds `assert`) |
| Assets | Four deployment-configured ERC20s | Hardcoding wstETH/GHO vs whatever `deploy.py` uses |
| Token | Non-transferable ERC1155 membership receipt | Tradeable NFT / soulbound marketing without “reverts on transfer” |
| ERC20 | Standard transfer semantics | Fee-on-transfer, rebasing, donation tokens |
| Admin | No pause / force tick / upgrade on instance | Emergency admin can freeze pools |
| onchain | one word | on-chain |

---

## Quick constants (code)

- `N = 10`
- `MISS_PENALTY_BPS = 5`
- `_DAYS_40 = 40 * 24 * 60 * 60`
- Supported asset count = 4 (addresses from constructor)

---

## Related docs

- `README.md` — contributor and integrator reference
- `docs/adr/README.md` — when to record irreversible decisions
