# Risks and fees

What you should evaluate before joining, and what the protocol may charge.

## Goal

Understand that Pasanaku is not a bank, fees are bounded, and vault performance is your risk.

## Not a bank

- You are in a fixed circle of **3, 6, 9, or 12** people with one asset per deployment.
- There is **no** guarantee against vault loss, insolvency, or liquidity shortfalls.
- The contract is not pauseable or upgradeable in the usual “admin rescue” sense — evaluate the deployment and the configured ERC-4626 vault yourself.
- The product may be in **beta**; parameters and UX can change for new pools.

Settlement continues even if the vault lost value; shortfalls are covered from the pool reserve when possible, and may still leave members with less than full principal.

## Fees

| Fee | Who pays | Who receives | Cap |
| --- | -------- | ------------ | --- |
| Creation fee | Creator (native ETH) | Protocol owner via collect | 0.001 ETH |
| Yield fee | Taken from end surplus | Protocol owner as underlying | 505 bps (5.05%) |
| Miss penalty | Misser’s collateral | **Pool reserve** (not owner) | 100 bps (1%) of principal reference |

Creation and yield fees are often set to zero; check the live deployment and create preflight in the app. Miss penalties always stay with the pool.

Owner configuration (fees, stale time) is documented for integrators in [Admin and fees](/guide/admin). Ordinary participants only need to know the fees that apply to their pool at create time (yield fee is snapshotted per pool).

## Vault and liquidity risk

| Risk | Effect |
| ---- | ------ |
| Vault share price falls | Less surplus or shortfalls at end / on miss recovery |
| Vault withdraw liquidity | Settlements that need vault exits can fail until liquidity returns |
| Wrong network / wrong asset | Transactions revert or you interact with the wrong deployment |

## Common mistakes

- Skipping due diligence on the vault behind the deployment.
- Assuming miss penalties enrich the protocol — they fund the pool reserve.
- Ignoring beta and fee settings shown at create time.

## See also

- [Yield and end](/user/yield-and-end)
- [Misses and stale pools](/user/misses-and-stale)
- [Glossary](/user/glossary)
- Implementation: [Admin and fees](/guide/admin), [End settlement](/guide/end-settlement)
