# P9.04 Parity matrix, runbook, and retrospective

Size: 2 points
Type: docs
Scope: platform
Red: skip

## Outcome

- A committed **platform parity matrix** doc exists with one row per platform (Claude Code, Codex, Cursor, VS Code/Copilot, Antigravity, OpenCode) and columns: config path(s) · events · tool names · native vs bridge · `source_origin` · support level (`verified` / `documented`).
- The matrix lists **OpenCode as deferred** with rationale (in-process TypeScript plugins, not shell hooks).
- The matrix/runbook documents the `.claude/settings.json` **bridge caveat** in one line ("VS Code may animate via the Claude bridge but mislabels until native install; prefer `hooks install --platform vscode`").
- Repo-level config surfaces (`​.github/hooks/`, workspace `.agents/hooks.json`) are documented as **manual opt-in**, distinct from the user-level paths the installer writes.
- `README.md` and `.son-of-anton/docs/template/overview/start-here.md` (or the repo's equivalent) reflect the two new `--platform vscode` / `--platform antigravity` flags and five-platform support.
- The `vscode`/`copilot` alias relationship is documented (canonical `vscode`; `copilot` accepted as alias).
- A retrospective is written at `docs/product/retrospectives/phase-09-extended-platform-hooks-retrospective.md` via the `soa-write-retrospective` skill.

## Red

- `Red: skip` — doc-only ticket (branch touches only `.md` files). No automated test; human review at the PR is the gate. Tests asserting exact doc wording would couple the suite to legitimate rewrites without quality signal.

## Green

- Write the parity matrix doc (suggested location: `docs/product/notes/public/` or alongside the existing hook runbook — match where the current hook runbook lives).
- Update README + start-here for the new flags and platform count.
- Write the retrospective covering: the build-from-docs + empirical-usage-validation playbook; the Antigravity-is-structurally-different lesson (no prompt event, `fullyIdle` terminal, `PostToolUse` has no tool name, dropped stepIdx correlation); the Copilot dual-dialect normalization; and any schema drift the developer found during real-usage validation of T02/T03.

## Refactor

- Keep doc cross-references consistent with the phase-08 → phase-09 ladder; fix any stale "Copilot CLI / VS Code Agent as separate surfaces" framing in linked notes if encountered (the decision is: one `vscode` surface).

## Review Focus

- Matrix accuracy against the as-shipped installers/classifiers (T02/T03) — config paths, events, and tool names must match what the code actually writes and classifies, not the original draft assumptions.
- Support-level column honesty: mark a platform `verified` only if the developer has confirmed it via real usage; otherwise `documented`.
- Bridge caveat is one line and points to native install; no detect/migrate behavior is implied (single-user, none built).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (doc-only, Red skip)
Why this path: Placed parity matrix in `docs/runbooks/` alongside the existing `phase-08-lite-install.md` and other per-phase runbooks — consistent location, easy to find. Alternative of `docs/product/notes/public/` would have mixed operator runbooks with internal planning notes.
Alternative considered: Combining parity matrix + retrospective into one doc — rejected; the matrix is a living operator reference that should not be interspersed with retrospective narrative.
Deferred: Real-usage validation attestation for vscode and antigravity — both remain `documented` until the developer runs a live session and confirms the payload shapes.
Contract note: None — Type: docs, Scope: platform matches delivery.
