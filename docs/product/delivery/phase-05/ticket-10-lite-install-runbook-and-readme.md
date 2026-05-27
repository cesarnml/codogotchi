# P5.10 Lite install runbook + README

Size: 2 points
Type: docs
Scope: runbooks
Red: skip

## Outcome

- `docs/runbooks/phase-05-lite-install.md` documents: Xcode Release build, install to `/Applications`, first launch, onboarding consent, hook install, expected idle → firing transition; explicitly **not** App Store.
- README updated: command table for `setup`, `rpg`, `hooks install|uninstall|status`; Lite vs Alive framing; link to runbook.
- **Cursor-via-Claude-bridge** section: third-party skills, `source_origin: claude_code` with Cursor tool names, native Cursor hooks deferred to Phase 06.
- **Demo mode:** documented as **developer QA only** (`--demo` / env) — not a user-facing Lite feature.
- Operator scripts cross-linked from runbook (backup / greenfield / restore).

## Red

- **`Red: skip`** — doc-only.

## Green

- Write runbook and README sections.
- Update `docs/template/overview/start-here.md` only if Phase 05 changes immediate next action for contributors.

## Refactor

- Scoped sweep; no full repo doc rewrite.

## Review Focus

- Copy is honest about hooks being required for a real install.
- No App Store implied as Phase 05 gate.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
