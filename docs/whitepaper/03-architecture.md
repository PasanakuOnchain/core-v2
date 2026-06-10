# 03. Architecture

Pasanaku is a **single non-upgradeable contract** that combines:

- Rotating savings pool logic (create, join, deposit, tick, end)
- Per-participant collateral ledger
- Per-pool ERC20 escrow (`pool_escrow`)
- Soulbound ERC-1155 membership receipts (metadata via `uri()`)

There are no external keeper contracts, no proxy, and no separate vault in core-v2.

## Actor diagram

User-facing roles and trust boundaries:

```mermaid
flowchart LR
    subgraph participants [Participants]
        Creator[Pool creator]
        Joiner[Joiners 2-10]
        Obligor[Round obligors]
        Recipient[Round recipient]
    end

    subgraph permissionless [Permissionless callers]
        Ticker[Any address — tick]
    end

    subgraph contract [Pasanaku contract]
        Collateral[collateral ledger]
        Escrow[pool_escrow per token_id]
        Payout[pending_payout ledger]
    end

    subgraph treasury [Protocol treasury]
        Owner[owner — penalties and ETH fees]
    end

    Creator -->|create_pasanaku + ETH fee| contract
    Joiner -->|join_pasanaku| contract
    Creator & Joiner -->|add_collateral| Collateral
    Obligor -->|deposit_to_pasanaku| Escrow
    Ticker -->|tick| contract
    contract -->|accrue| Payout
    Recipient -->|claim_round_payout| Recipient
    contract -->|miss penalties ERC20| Owner
    Creator -->|create fee ETH| contract
    Owner -->|collect_fees| Owner
```

| Actor | Role | Trust required |
|-------|------|----------------|
| **Participant** | Collateral, create/join, deposit, claim | Contract math and ERC20 |
| **Permissionless tick caller** | Advances rounds after 40 days | None — public function |
| **Owner** | Receives penalties and ETH fees; sets fee and stale time | Does not control tick or payouts |
| **Recipient** | Must actively claim each round payout | Contract will hold until claim |

For contract-internal step order, see [protocol-flow.md](../protocol-flow.md).

## Money flow

How ERC20 and ETH move through the system:

```mermaid
flowchart TB
    subgraph inbound [Inbound]
        AddCol[add_collateral — ERC20 in]
        CreateFee[create_pasanaku — ETH fee in]
        Deposit[deposit_to_pasanaku — ERC20 to pool_escrow]
    end

    subgraph locked [Locked on contract]
        Pledge[collateral_in_use — pledge per pool]
        Escrow[pool_escrow — round deposits and slash credits]
        Pending[pending_payout — accrued principal]
    end

    subgraph outbound [Outbound]
        Claim[claim_round_payout — ERC20 to recipient]
        Penalty[miss penalty — ERC20 to owner]
        Withdraw[withdraw_collateral — free ERC20 out]
        Unlock[end pool — pledge released]
        EthOut[collect_fees — ETH to owner]
    end

    AddCol --> Pledge
    CreateFee --> contract[(Pasanaku ETH balance)]
    Deposit --> Escrow
    Escrow -->|tick settle| Pending
    Escrow -->|tick miss| Penalty
    Pledge -->|slash on miss| Escrow
    Pending --> Claim
    Pledge --> Unlock
    Pledge --> Withdraw
    contract --> EthOut
```

**Collateral vs escrow:** Collateral backs obligations and absorbs slashes. Round deposits sit in `pool_escrow` until tick moves value to `pending_payout` or penalties.

## Key storage surfaces

| Ledger | Purpose |
|--------|---------|
| `_collateral[account][asset]` | Participant-funded backing |
| `_collateral_in_use[account][asset]` | Pledged portion per active pool |
| `_pool_escrow[token_id]` | Per-pool ERC20 attribution |
| `_pending_payout[token_id][round_idx]` | Accrued recipient principal |
| `_pasanakus[token_id]` | Pool struct (participants, index, timestamps) |

## Architecture decisions

- [ADR-0001: Pull-claim payouts](../adr/0001-pull-claim-payouts.md)
- [ADR-0002: No single active pool cap](../adr/0002-no-single-active-pool-cap.md)
- [ADR-0003: Stale pending exit](../adr/0003-stale-pending-exit.md)

---

> **Implemented today**
>
> Single-contract deployment with the actors and ledgers above. Diagrams match `src/Pasanaku.vy`. Integrator views: [README.md](../../README.md) — Integrator / indexer playbook.
