# Glossary

Short definitions for terms you will see in the app and this user guide.

| Term | Meaning |
| ---- | ------- |
| **Pasanaku** | A fixed-membership rotating savings pool (also the product name). |
| **Circle / pool** | One pasanaku instance identified by a pool ID. |
| **Participants** | Exactly **6** or **12** members; chosen at create and locked at start. |
| **Per-round amount** | Fixed asset amount each obligor deposits in a round. |
| **Pledge** | Locked collateral to create/join: `per-round × N` plus **1%** miss headroom. |
| **Free collateral** | Shares you can withdraw or pledge. |
| **Locked collateral** | Shares committed to a pool until end or leave (pending/stale). |
| **Vault / ERC-4626** | Yield-bearing vault that holds collateral; the contract owns the shares. |
| **Pending / Open** | Pool not started; still filling (or waiting). |
| **Stale** | Fill window expired; joins blocked; members may leave. |
| **Active / Started** | Rounds in progress. |
| **Ended** | Final settlement done. |
| **Start** | Roster full: shuffle, membership mint, yield accounting begins. |
| **Payout order / position** | Shuffled recipient sequence (`#1` … `#N`); set at start. |
| **Round** | One contribution window and one recipient turn. |
| **Obligor** | Member who must deposit this round (not the recipient). |
| **Recipient** | Member who claims that round’s pot after tick. |
| **Deposit (round)** | Pay the per-round amount into the pool for a participant. |
| **Tick** | Permissionless settle after ≥ **28 days**; accrues pending payout / may end the pool. |
| **Claim** | Recipient pulls a pending round payout. |
| **Pull payout** | Funds wait until claim; later ticks do not require prior claims. |
| **Pool reserve** | Shares from miss penalties (and related cover), owned by the pool. |
| **Miss** | Obligor did not deposit before tick; collateral may cover + 1% penalty. |
| **Yield / surplus** | Vault appreciation after start, shared at end by position weights. |
| **Yield fee** | Optional cut of end surplus to the protocol owner (capped; snapshotted at create). |
| **Creation fee** | Optional native ETH fee to create a pool (capped). |
| **Membership receipt** | Soulbound ERC-1155 minted at start; not transferable. |
| **Base** | Target chain for production deployments. |

## See also

- [Getting started](/user/getting-started)
- [What is a pasanaku?](/user/what-is-pasanaku)
- Implementation: [Reference](/guide/reference), repository `CONTEXT.md`
