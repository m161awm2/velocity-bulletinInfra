# Domain Docs

Before exploring the codebase, read the root `CONTEXT.md` and relevant ADRs under `docs/adr/`. If these files do not exist, proceed silently; the domain-modeling workflow creates them when needed.

## File structure

This repository uses a single-context layout:

```
/
├── CONTEXT.md
├── docs/adr/
└── src/
```

Use terminology defined in `CONTEXT.md`. Explicitly flag output that conflicts with an existing ADR instead of silently overriding the decision.
