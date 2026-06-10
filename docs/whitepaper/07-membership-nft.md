# 07. Membership NFT

Each started pasanaku pool issues an **ERC-1155 membership receipt** — one token (amount 1) per participant, keyed by pool `token_id`.

## Soulbound today

Membership tokens are **non-transferable**:

- `safeTransferFrom`, `safeBatchTransferFrom`, and `setApprovalForAll` revert with `"pasanaku: pasanakus are soul-bounded tokens"`.
- `isApprovedForAll` always returns `false`.

The NFT is a **wallet-visible membership record**, not a tradable asset. Minting uses `_mint` without receiver callback so contract-wallet participants are supported.

## Metadata via `uri(token_id)`

The `uri()` view returns IPFS metadata reflecting pool state:

| State | Condition | Purpose |
|-------|-----------|---------|
| **pending** | Created, not started, not stale | Pool filling |
| **stale** | Pending and past `stale_time` | Exit eligible |
| **ongoing** | Started, not ended | Active rounds |
| **ended** | After final tick | Historical record |

Integrators and wallets should use `uri()` for display badges and explorer links.

## What the NFT is not

- Not proof of payout — use `pending_payout`, `deposited_for_pasanaku`, and events.
- Not tradable on secondary markets in core-v2.
- Not a governance token.

## Future tradability — vision only

> **Planned (not deployed)**
>
> A future version might allow transferable membership or fractional pool shares. That would require new contract logic and is **not** current behavior. Until then, document transfers as reverting.

---

> **Implemented today**
>
> Soulbound ERC-1155 with stateful `uri()` in `src/Pasanaku.vy`. See [README.md](../../README.md) — ERC-1155 membership metadata.
