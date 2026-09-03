# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase. **Layout: single-context.**

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the domain glossary for Cooked (event taxonomy, macro/micro/engagement conversions, page types, channel taxonomy…).
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist yet, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The producer skill (`/grill-with-docs`) creates them lazily when terms or decisions actually get resolved.

> Both exist since 2026: `CONTEXT.md` (13/07/2026 — conversions, attribution, lecture, fraîcheur, invariants) and `docs/adr/` (ADR-0001 28/07/2026, ADR-0002 23/08/2026). Read them first; `CLAUDE.md` carries the operating rules, `CONTEXT.md` the vocabulary.

## File structure (single-context)

```
/
├── CONTEXT.md            ← domain glossary for Cooked
├── docs/adr/             ← architectural decision records
│   ├── 0001-....md
│   └── 0002-....md
└── ...
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md` (or, for now, the conventions in `CLAUDE.md`). Don't drift to synonyms the glossary explicitly avoids — e.g. keep the macro / micro / engagement distinction, always say `events_human` (not `events`), and never conflate "contacts" with "booking_intent".

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0003 (chrome anchors excluded from events_human) — but worth reopening because…_
