# Architecture Decision Records (ADRs)

Lightweight log for **hard-to-reverse** or **surprising** choices in Pasanaku. Not every PR needs an ADR.

## When to write an ADR

Create an ADR when a decision is:

1. **Hard to reverse** — changes economics, storage layout, external interfaces, or deployment topology in ways that are costly to undo.
2. **Surprising** — reasonable readers would assume the opposite (e.g. “one pool per asset” while code only counts actives).
3. **A real trade-off** — you rejected a viable alternative for explicit reasons (gas, trust model, UX, operability).

Skip ADRs for:

- Bug fixes that restore intended behavior
- Test-only or tooling changes
- Renames and formatting
- Documenting what the code already does (use README / `CONTEXT.md` instead)

## Naming convention

```
docs/adr/NNNN-short-kebab-title.md
```

- `NNNN` — four-digit sequence (`0001`, `0002`, …)
- `short-kebab-title` — lowercase words, no spaces

Example: `docs/adr/0001-no-single-active-pool-enforcement.md`

## Status values

Use one of: **Proposed**, **Accepted**, **Deprecated**, **Superseded by ADR-XXXX**

## Minimal template

Copy into a new file and fill in:

```markdown
# NNNN. Title in plain language

- Status: Accepted
- Date: YYYY-MM-DD

## Context

What problem or constraint forced a decision?

## Decision

What we chose, in one or two paragraphs.

## Consequences

### Positive

- …

### Negative / risks

- …

## Alternatives considered

- **Alternative A** — why not
- **Alternative B** — why not
```

Keep ADRs short (one screen preferred). Link to issues or PRs when helpful.

## Relationship to other docs

| Doc | Role |
|-----|------|
| `src/Pasanaku.vy` | Canonical behavior |
| `CONTEXT.md` | Stable domain language for agents |
| `README.md` | How the protocol works today + dev workflow |
| `docs/adr/*.md` | Why we chose a non-obvious path |

If an ADR and the contract disagree, **fix the contract or supersede the ADR** — do not leave both authoritative.
