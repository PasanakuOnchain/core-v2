# 🔐 Security Review — core-v2

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | default                                                |
| **Files reviewed**               | `Pasanaku.sol` · `LibLayoutUtils.sol` · `TokenDescriptor.sol`<br>`LayoutOngoing.sol` · `LayoutEnded.sol` |
| **Confidence threshold (1-100)** | 75                                                     |

---

## Findings

[92] **1. Single `recover` sets a global `recovered` flag that bricks deposits and claims for everyone**

`Pasanaku.recover` · Confidence: 92 · [agents: 1,2,3,4,5,6]

**Description**

`recover` sets `rs.recovered = true` on the shared `RotatingSavings` struct while `_canDeposit` and `_canClaim` require `!rs.recovered` for all participants, so one eligible participant’s recovery can permanently freeze the round for every other participant and strand residual ERC-20 in the pool with no remaining claim path.

**Fix**

```diff
- rs.recovered = true;
+ // Use per-participant recovery flags or round-scoped exit; avoid a single global bool
+ // that gates _canDeposit/_canClaim for every participant.
```

**Fix verification (confidence ≥ 80):** Replace the global flag with per-address recovery tracking (or a defined wind-down state machine), re-run the trace: first recoverer no longer sets `!rs.recovered` for others; `_canDeposit` / `_canClaim` remain reachable until the round is legitimately completed or cancelled; `SafeTransferLib` paths unchanged for reentrancy; no new underflow in `totalDeposited` without matching token movements.

---

[86] **2. Economic rights follow static `participants[]`, not current ERC1155 balance**

`Pasanaku.claim` · `Pasanaku.deposit` · `Pasanaku.skip` · Confidence: 86 · [agents: 1,8]

**Description**

`create` mints to roster addresses and all checks use `msg.sender` against `participants`, but never require `balanceOf(msg.sender, tokenId) > 0`, so a listed address can transfer the ERC1155 share away and still call `claim` / `deposit` / `skip`, while a buyer of the NFT cannot act unless they control the original participant address.

**Fix**

```diff
+ if (balanceOf(msg.sender, tokenId) < TOKEN_AMOUNT) revert ...;
   ...
```

(Apply the same guard on `deposit`, `claim`, and `skip`, or enforce soul-bound / transfer-restricted shares via `_beforeTokenTransfer`.)

**Fix verification:** After adding the balance check, an address that transferred its share reverts on `claim`; a holder who is not in `participants` still cannot act—if the intended model is “rights follow the NFT”, also update `participants` on transfer in `_beforeTokenTransfer`; otherwise document non-transferable seats.

---

[82] **3. Uncapped `10 ** decimals` in `formatWithDecimals` can panic-revert metadata views**

`LibLayoutUtils.formatWithDecimals` · Confidence: 82 · [agents: 2,7,8]

**Description**

`divisor = 10 ** decimals` uses `decimals` from `IERC20Metadata(asset).decimals()` without a cap; for sufficiently large `decimals` (including values above ~77), the exponentiation overflows in 0.8.x and reverts, bricking `layout` / `tokenURI` for that pool.

**Fix**

```diff
- uint256 divisor = 10 ** decimals;
+ if (decimals > 77) decimals = 18; // or bound to IERC20Metadata expectations
+ uint256 divisor = 10 ** decimals;
```

**Fix verification:** With `decimals = 78`, view calls no longer revert at `10 ** decimals`; pick a cap consistent with supported assets (e.g. 18) and document it.

---

[78] **4. Unbounded `symbol()` is concatenated into on-chain SVG**

`LayoutOngoing._imageData` · `LayoutEnded._imageData` · Confidence: 78 · [agents: 7]

**Description**

`IERC20Metadata(asset).symbol()` is inlined into a large SVG string with no maximum length; a malicious or buggy token can return a multi-megabyte string and cause `tokenURI` / `eth_call` to hit gas limits or fail, denying metadata to integrators.

**Fix**

```diff
- string memory symbol = IERC20Metadata(asset).symbol();
+ string memory symbol = _truncate(IERC20Metadata(asset).symbol(), 32);
```

**Fix verification:** Long symbols truncate deterministically; gas for `tokenURI` stays bounded; Base64 / JSON pipeline unchanged aside from shorter input.

---

[75] **5. NatSpec lists ten assets while `SUPPORTED_ASSETS_COUNT` is nine**

`Pasanaku` (constructor / constants) · Confidence: 75 · [agents: 1,2,6,8]

**Description**

Comments enumerate ten tickers but the constructor only accepts `address[9]`, so deployment cannot match the documented allowlist without a code change.

---

## Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [92] | Single recover sets global flag that bricks deposits and claims |
| 2 | [86] | Rights follow participant list, not ERC1155 balance |
| 3 | [82] | Uncapped `10 ** decimals` can revert metadata formatting |
| 4 | [78] | Unbounded `symbol()` can gas-DoS on-chain SVG |
| 5 | [75] | Nine-slot array vs ten-asset NatSpec |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **Claimed event `totalDeposited` field duplicates payout** — `Pasanaku._applyRound` — Code smells: fifth argument to `Claimed` mirrors the payout amount after `rs.totalDeposited` was zeroed — Indexers treating the field as post-state cumulative balance will mis-account; observability only.

- **Deposit updates accounting before `safeTransferFrom`** — `Pasanaku.deposit` — Code smells: CEI order with effects before pull; `create` uses `nonReentrant` but `deposit`/`claim`/`skip`/`recover` do not — Standard ERC-20s do not reenter; ERC-777-style hooks could theoretically couple with nested calls — verify asset list and add `nonReentrant` or pull-then-settle if exotic tokens are ever allowed.

- **`recover` calls `_burn` before storage updates** — `Pasanaku.recover` — Code smells: ERC1155 receiver callback could observe stale `totalDeposited` / `_deposited` if hooks were enabled — Low risk with current Solady defaults; worth reordering or guarding if `onERC1155Received` becomes relevant.

- **Empty `uri(uint256)` override** — `Pasanaku.uri` — Code smells: EIP-1155 `uri` returns `""` — Marketplaces that only call `uri(id)` miss rich metadata unless they use `TokenDescriptor`.

- **Fee-on-transfer / rebasing assumptions** — `Pasanaku.deposit` / `_applyRound` — Code smells: Accounting uses `rs.amount` increments vs actual balance deltas — Safe if allowlist is correct; misconfiguration could desync balances and claims.

- **Constructor asset list vs comment (operational)** — `Pasanaku` — Code smells: nine slots vs ten names — Deployment checklist should match code.

- **JSON / SVG embedding** — `TokenDescriptor.tokenURI` / layouts — Code smells: `imageURI` and traits built via `string.concat` without general JSON escaping — Current `data:` + Base64 paths are narrow; future changes could introduce quote breaks.

- **Economic timing (claim vs recover delay)** — `Pasanaku` — Code smells: Beneficiary may claim immediately after quorum; depositors wait 30 days for `recover` — Intentional asymmetry for many rotating-credit designs; confirm product intent.

---

**Chain (optional):** [1] Single global `recovered` + [2] seat vs NFT holder — Combined impact: a recovering participant can freeze the round while the current beneficiary’s rights still depend on a static address, compounding coordination failures for secondary holders. Confidence: min(92,86) → treat as related but distinct mechanisms.

---

> This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
