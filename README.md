# Moccasin Project

🐍 Welcome to your Moccasin project!

## Pasanaku v1 model

Pasanaku is a rotating savings pool with collateral-backed rounds:

- **Nine participants** join a pool; each round one member receives `(N-1) × amount` in principal from obligor deposits.
- **Collateral** is locked when creating or joining a pool and enforces missed-deposit penalties (slashed to the contract owner).
- **Round deposits** are plain ERC20 escrow on the Pasanaku contract — no external lending protocol.
- **One active pool per asset**: at most one started, not-yet-ended pasanaku may be active for each supported ERC20 at a time. Pending pools for the same asset may coexist.

## Quickstart

1. Deploy to a fake local network that titanoboa automatically spins up!

```bash
mox run deploy
```

2. Run tests

```
mox test
```

_For documentation, please run `mox --help` or visit [the Moccasin documentation](https://cyfrin.github.io/moccasin)_
