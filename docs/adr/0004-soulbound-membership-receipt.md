# 0004. Soulbound membership receipt

- Status: Accepted
- Date: 2026-06-10

## Context

Each started pasanaku pool mints an ERC-1155 token (amount 1) per participant, keyed by pool `token_id`. Wallets and explorers use `uri()` for state badges (pending, stale, ongoing, ended).

Two models were available for membership tokens:

1. **Transferable** — standard ERC-1155; participants could sell or delegate membership.
2. **Soulbound** — transfers and approvals revert; membership is tied to the joining address.

ROSCA membership is economically meaningful: the holder has obligor duties, collateral at risk, and future payout rights. Allowing transfers would let someone join, receive collateral backing from the protocol’s pledge lock, and sell the slot before fulfilling nine rounds of deposits — shifting default risk to a buyer who may not have funded collateral.

## Decision

Membership receipts are **soulbound** in core-v2:

- `safeTransferFrom`, `safeBatchTransferFrom`, and `setApprovalForAll` revert with `"pasanaku: pasanakus are soul-bounded tokens"`.
- `isApprovedForAll` always returns `false`.
- Minting uses internal `_mint` without ERC-1155 receiver callback so contract-wallet participants are supported.

The NFT is a **membership record for display and indexing**, not a tradable asset.

## Consequences

### Positive

- Membership stays aligned with the address that locked `pledge(amount)`.
- No secondary-market slot sales that decouple economic obligation from collateral.
- Simpler integrator model — one participant address per pool slot.

### Negative / risks

- Participants cannot exit by selling membership; only stale pending `leave_pasanaku` or completing the pool applies.
- Wallets cannot treat receipts as generic transferable collectibles.
- Any future tradability requires a new deployment or explicit contract change.

## Alternatives considered

- **Fully transferable ERC-1155** — enables secondary markets but breaks the join-address ↔ collateral invariant unless transfers also move pledge locks (not implemented).
- **Non-ERC-1155 membership flag** — avoids NFT expectations but loses wallet visibility and metadata standards; rejected for UX.
- **Transferable with collateral handoff** — viable future design; out of scope for core-v2 minimal surface.

## Future tradability (not deployed)

A future version might allow transferable membership or fractional pool shares with explicit collateral migration rules. Until then, document and implement transfers as reverting. Public narrative may mention optional future tradability only with a **not deployed** qualifier — see [whitepaper.md](../whitepaper.md) and [07 — Membership NFT](../whitepaper/07-membership-nft.md).
