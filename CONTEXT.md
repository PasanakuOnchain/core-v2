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

**Language:** Permissionless `tick(token_id)` after `updated + 40 days`. Settles current round, accrues principal to `pending_payout`, accrues miss penalties to `pending_penalties`, advances index or ends pool.

**Relationships:** Emits `PasanakuTicked`; may emit `PasanakuPenalties`. Recipient claims ERC20 via `claim_round_payout`. Penalties transfer to `owner()` only via later `claim_penalties`. Not callable by owner exclusively.

**Example dialogue:**
- ✅ “Anyone can tick once the 40-day window elapses.”
- ❌ “The protocol admin must tick each round.”
- ❌ “Tick sends principal directly to the recipient’s wallet.” (recipient must `claim_round_payout`)
- ❌ “Tick pushes miss penalties to owner as an ERC20 transfer.” (accrues to `pending_penalties`; claim later)

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

**Relationships:** Accrues to `_pending_penalties[asset]` on tick (`PasanakuPenalties`); anyone may later call `claim_penalties(asset)` to transfer to current `owner()` (`PenaltiesClaimed`). Does not reduce recipient’s `amount` credit for that obligor. View: `pending_penalties(asset)`.

**Example dialogue:**
- ✅ “Penalty is 0.05% of the per-round amount, accrued then claimed to treasury.”
- ❌ “A miss only costs the penalty, not the round principal.”
- ❌ “Tick transfers the penalty ERC20 to owner immediately.”

---

### Treasury sink

**Language:** `owner()` receives aggregated miss penalties (ERC20 via `claim_penalties`) and creation fees (ETH via `collect_fees()`), not obligor principal.

**Relationships:** Ownable two-step; economically relevant but does not operate rounds. Configures `set_fee` and `set_stale_time`.

**Example dialogue:**
- ✅ “Treasury earned 0.4 USDC in penalties after claim_penalties.”
- ❌ “Owner can redirect recipient payouts.”
- ❌ “Penalties land in the owner wallet inside the tick transaction.”

---

### Creation fee (ETH)

**Language:** Native ETH required on `create_pasanaku` only. View: `fee()`. Owner sets via `set_fee` (0 to 0.001 ETH). Swept via `collect_fees()`.

**Relationships:** Distinct from ERC20 collateral and miss penalties. Default is **0** at deploy. `join_pasanaku` is free of ETH.

**Example dialogue:**
- ✅ “Pool creation costs 0.0005 ETH plus the USDC pledge lock.”
- ❌ “Participants pay a fee each round.” (only create, not deposit)

---

### collect_fees

**Language:** Owner-only `collect_fees()` — transfers the contract’s native ETH balance to `owner()`. Emits `FeesCollected`. Used for accumulated creation fees from `create_pasanaku`.

**Relationships:** Does not sweep ERC20 (miss penalties are claimed via `claim_penalties`). Distinct from `withdraw_collateral`. Requires successful ETH transfer to owner.

**Example dialogue:**
- ✅ “Owner called collect_fees after ten pools were created at 0.0001 ETH each.”
- ❌ “collect_fees pulls USDC penalties.” (penalties are ERC20 via `claim_penalties`, not ETH sweep)

---

### Stale pool / leave_pasanaku

**Language:** Pending pool (`started == 0`) where `created + stale_time <= now`. Participants may `leave_pasanaku(token_id)` to unlock pledged collateral and exit. `_remove_from_array` shifts subsequent members down, preserving relative join order of remaining participants (not swap-with-last).

**Relationships:** `stale_time` is 3–7 days (default 7), set by owner via `set_stale_time`. Emits `PasanakuLeft`. ERC-1155 `uri()` returns stale metadata when eligible.

**Example dialogue:**
- ✅ “Pool 12 is stale with 4/10 members; Alice called leave_pasanaku.”
- ✅ “After Bob left mid-list, Carol stayed ahead of Dan in join order.”
- ❌ “Stale pools auto-cancel and refund everyone.” (each participant must leave individually)
- ❌ “Leave swaps the leaver with the last participant.”

---

### Pull claim

**Language:** Delivery model for both recipient principal and miss penalties: `tick` accrues; later calls transfer ERC20. Principal: `pending_payout` / `claim_round_payout`. Penalties: `pending_penalties` / permissionless `claim_penalties` to current `owner()`.

**Relationships:** Pool index advances on tick even if claim is delayed. See ADR-0001.

**Example dialogue:**
- ✅ “After tick, the recipient pulls payout via claim_round_payout.”
- ✅ “Anyone can call claim_penalties to send accrued penalties to owner.”
- ❌ “Tick automatically sends tokens to the recipient wallet.”
- ❌ “Tick automatically sends penalty tokens to owner.”

---

### Protocol vision vs deployed behavior

**Language:** **Deployed today:** collateral-backed ROSCA pools, soulbound ERC-1155, Ownable admin (`owner()` treasury), permissionless tick. **Not deployed:** NAKU token governance, fee distribution to stakers, tradable membership NFTs.

**Relationships:** Future vision belongs in `docs/whitepaper.md` (Roadmap) and `docs/whitepaper/09-protocol-vision.md`. Do not imply NAKU or token-holder revenue exists onchain in core-v2.

**Example dialogue:**
- ✅ “Today penalties go to owner() via claim_penalties; NAKU staker fee share is a planned upgrade.”
- ❌ “Token holders receive protocol fees.” (without “planned / not deployed” qualifier)

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

**Relationships:** Credited on `deposit_to_pasanaku` and miss slashes in `_settle_round`; debited on payout accrual and penalty accrual to `pending_penalties`. Isolates concurrent same-asset pools.

**Example dialogue:**
- ✅ “Pool B’s `pool_escrow` is unchanged after pool A ticks.”
- ❌ “All deposits share one fungible pot with no per-pool ledger.”

---

### pending_payout / claim_round_payout

**Language:** `pending_payout(token_id, round_idx)` holds accrued principal after `tick`. `claim_round_payout(token_id, round_idx)` transfers ERC20 to `participants[round_idx]` only.

**Relationships:** Pool advances on `tick` even if claim is delayed. Distinct from collateral, obligor deposit escrow, and `pending_penalties`.

**Example dialogue:**
- ✅ “Recipient called `claim_round_payout(3, 2)` after round 2 ticked.”
- ❌ “Principal arrives in the recipient wallet inside the same `tick` transaction.”

---

### pending_penalties / claim_penalties

**Language:** `pending_penalties(asset)` holds accrued miss penalties after `tick`. Permissionless `claim_penalties(asset)` transfers the balance to current `owner()` and emits `PenaltiesClaimed`.

**Relationships:** Accrued via `_distribute_penalties` on tick (`PasanakuPenalties` logs accrual). `tick` never ERC20-transfers penalties to owner. Distinct from `claim_round_payout` and `collect_fees`.

**Example dialogue:**
- ✅ “After three ticks with misses, claim_penalties(USDC) sent 0.15 USDC to owner.”
- ❌ “Tick transfers penalty ERC20 to owner in the same transaction.”

---

## Correct vs incorrect wording

| Topic | ✅ Say | ❌ Avoid |
|-------|--------|----------|
| Decentralization | Permissionless settlement; collateralized obligations | “100% trustless” / “no privileged roles” (owner + treasury exist) |
| amount | Per-round obligor deposit in raw token units | Total savings goal or TVL |
| pledge | `amount*N` plus penalty reserve | Same as single `amount` |
| Payout | `(N-1) * amount` principal to recipient | `N * amount` |
| Payout delivery | Recipient calls `claim_round_payout` after tick | Tick sends ERC20 directly to recipient wallet |
| Penalty delivery | Accrue to `pending_penalties`; `claim_penalties` to owner | Tick pushes penalty ERC20 to owner |
| Leave order | Shift-down; remaining members keep relative join order | Swap-with-last on leave |
| Penalty | 0.05% of `amount` per miss (5 bps) | 5% penalty |
| Pools per asset | Counter; multiple active allowed | “One active pool per asset” (unless code adds `assert`) |
| Assets | Four deployment-configured ERC20s | Hardcoding wstETH/GHO vs whatever `deploy.py` uses |
| Token | Non-transferable ERC1155 membership receipt | Tradeable NFT / soulbound marketing without “reverts on transfer” |
| Governance (today) | Ownable two-step admin: `set_fee`, `set_stale_time`, `collect_fees`; treasury via `owner()` | NAKU token votes or staker fee share exist today |
| NAKU / governance (roadmap) | Planned only — not in core-v2 | Token holders earn fees today |
| ERC20 | Standard transfer semantics | Fee-on-transfer, rebasing, donation tokens |
| Admin | No pause / force tick / upgrade on instance | Emergency admin can freeze pools |
| onchain | one word | on-chain |

---

## Quick constants (code)

- `N = 10`
- `MISS_PENALTY_BPS = 5`
- `_DAYS_40 = 40 * 24 * 60 * 60`
- `_DAYS_3` / `_DAYS_7` — stale window bounds (default 7 days)
- `_MAX_FEE = 0.001 ETH` — creation fee cap
- Supported asset count = 4 (addresses from constructor)

---

## Related docs

- `README.md` — contributor and integrator reference
- `docs/README.md` — documentation hub
- `docs/whitepaper.md` — public-facing whitepaper
- `docs/whitepaper/` — extended chapter-by-chapter narrative
- `docs/adr/README.md` — when to record irreversible decisions
