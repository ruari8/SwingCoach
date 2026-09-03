# Domain docs

This file tells the engineering skills how to read this repo's domain documentation before exploring the codebase.

## Before exploring, read these

- `CONTEXT.md` at the repo root.
- `CONTEXT-MAP.md` at the repo root, if it exists. It points to one `CONTEXT.md` per context. Read each one relevant to the task.
- Relevant ADRs under `docs/adr/`. In a multi-context repo, also check `src/<context>/docs/adr/` for context-specific decisions.

If any of these files do not exist, proceed without flagging their absence or suggesting that they be created first. The `/domain-modeling` skill creates them when the team resolves terms or decisions.

## File structure

SwingCoach uses the single-context layout:

```text
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-example-decision.md
│   └── 0002-another-decision.md
├── SwingCoach/
└── backend/
```

A multi-context repo instead has a root `CONTEXT-MAP.md` that points to context-specific `CONTEXT.md` files and ADR directories.

## Use the glossary's vocabulary

When output names a domain concept in an issue title, proposal, hypothesis, or test, use the term defined in `CONTEXT.md`. Do not substitute a synonym that the glossary rejects.

If the concept is missing from the glossary, reconsider whether the project uses that language. If the gap is real, note it for `/domain-modeling`.

## Flag ADR conflicts

If output contradicts an existing ADR, say so instead of silently overriding it. Name the ADR and explain why the decision may need to change.
