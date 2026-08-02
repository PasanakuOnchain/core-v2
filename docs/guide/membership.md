# ERC-1155 membership

At start, every participant receives one soulbound ERC-1155 membership receipt for the pool's `token_id`. The token is a membership signal and metadata hook—not transferable collateral.

## Mint

`_mint_membership_token` writes directly into the snekmate ERC-1155 module storage:

- `total_supply[token_id] += 1`
- `balanceOf[owner][token_id] += 1`
- emits `TransferSingle` from the zero address

`_TOKEN_AMOUNT` is always `1`.

## Soulbound surface

These entry points always revert with `pasanaku: pasanakus are soul-bounded tokens`:

- `safeTransferFrom`
- `safeBatchTransferFrom`
- `setApprovalForAll`

`isApprovedForAll` always returns `false`.

Exported module helpers that remain available include `supportsInterface`, `balanceOfBatch`, `exists`, and `total_supply`, plus the local `balanceOf` view.

## `uri` states

`uri(token_id)` selects a fixed IPFS CID from lifecycle state:

| State | Condition |
| --- | --- |
| Not created | `token_id >= _counter` |
| Ended | `ended != 0` |
| Ongoing | `started != 0` |
| Stale | pending and `created + stale_time <= now` |
| Pending | otherwise |

Constants used in tests (`URI_NOT_CREATED`, `URI_ENDED`, `URI_ONGOING`, `URI_STALE`, `URI_PENDING`) match these branches.

## Ownership modules

The contract initializes snekmate `ownable` + `ownable_2step` and re-exports:

- `owner`, `pending_owner`
- `transfer_ownership`, `accept_ownership`, `renounce_ownership`

Membership minting is not gated by ownership; it runs inside `_start_pasanaku`.

## See also

- [Start and shuffle](./start-and-shuffle.md)
- `CONTEXT.md` — ERC-1155 membership
- `tests/unitary/erc1155/test_membership_mint.py`, `test_soulbound.py`, `test_uri.py`
