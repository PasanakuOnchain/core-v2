# Pasanaku – Decentralized Rotating Savings Protocol

A trustless onchain rotating savings protocol (rosca/cundina). Participants create a savings circle, deposit a fixed amount each round, and take turns claiming the full pot.

Built with Solidity 0.8.33, [Foundry](https://book.getfoundry.sh/), and [Solady](https://github.com/Vectorized/solady).

---

## What is Pasanaku?

Pasanaku brings the traditional rotating savings model (known as roscas, cundinas, or tandas) onchain. A group of participants agrees to contribute a fixed amount in a chosen asset each round. Each round, one participant receives the pooled funds; the order rotates until everyone has been paid out. The protocol is trusted—smart contracts enforce deposits and claims with no central custodian.

---

## Features

- **Create savings circles** – Set participants, ERC20 asset, and per-round amount (max 12 participants)
- **Deposit & claim** – Participants deposit each round; the current beneficiary claims the pot
- **30-day recovery** – Non-beneficiaries can recover their deposit if the beneficiary fails to claim in time
- **ERC1155 participation tokens** – Each participant holds a token representing their stake in a given savings
- **Dynamic SVG metadata** – TokenDescriptor renders onchain SVG images via LayoutOngoing (active) and LayoutEnded (completed)
- **Whitelisted assets** – Supports up to 9 configurable ERC20 assets

---

## Project Structure

```
src/
├── Pasanaku.sol              # Main rotating savings contract
├── interfaces/
│   ├── IPasanaku.sol         # RotatingSavings struct
│   ├── ILayout.sol           # Metadata layout interface
│   └── IERC20Metadata.sol
├── metadata/
│   ├── TokenDescriptor.sol   # ERC1155 token URI generation
│   └── layouts/
│       ├── LayoutOngoing.sol # SVG for active savings
│       └── LayoutEnded.sol   # SVG for completed savings
└── utils/
    └── LibLayoutUtils.sol    # Formatting helpers for SVG

test/
├── Pasanaku.t.sol            # Core protocol tests
├── LayoutOngoing.t.sol       # Ongoing layout tests
├── LayoutEnded.t.sol         # Ended layout tests
├── TokenDescriptor.t.sol     # Token Descriptor tests
└── _mocks/
    ├── MockERC20.sol
    └── MockERC20Metadata.sol

lib/
├── forge-std/                # Foundry standard library
└── solady/                   # Solady contracts
```

See [remappings.txt](remappings.txt) for `forge-std` and `solady` path mappings.

---

## Requirements

- [Foundry](https://book.getfoundry.sh/) (Forge, Cast, Anvil)

---

## Quick Start

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

For advanced Foundry usage (deploy, cast, anvil), see the [Foundry book](https://book.getfoundry.sh/).

---

## Testing

The test suite covers:

- **Pasanaku.t.sol** – Core protocol logic: create, deposit, claim, recover, and view functions
- **LayoutOngoing.t.sol** – SVG layout for active savings (round, deposits, currency)
- **LayoutEnded.t.sol** – SVG layout for completed savings (total distributed, players, creator)

---

## Dependencies

- [forge-std](https://github.com/foundry-rs/forge-std) – Foundry standard library
- [Solady](https://github.com/Vectorized/solady) – ERC1155, Ownable, SafeTransferLib, Base64, LibString

---

## Author

Rafael Abuawad – [@rabuawad_](https://x.com/rabuawad_)

---

## License and Disclaimer

This code is for **testing purposes only**. It is **not production ready** and **has not been audited**. Everything is subject to change. Use at your own risk. See [LICENSE](LICENSE) for license terms.
