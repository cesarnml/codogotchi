# P14.09 Docs sweep + v2.1.0 bump + retrospective

Size: 2 points
Type: docs
Scope: docs
Red: skip

## Outcome

- `README.md` reflects per-platform pet assignment, the Minimalist display mode, the retired `config.pet` CLI command (breaking-change note), and the new `assignments.json` contract.
- `docs/template/overview/start-here.md` (or the repo's status/overview doc) reflects the delivered Phase 14 scope, commands, and deferrals.
- Cross-agent visualization behavior is documented: a subagent on another platform legitimately spawns that platform's transient pet window, which ages out via the existing TTL — expected, not a bug.
- App version is bumped to **2.1.0** in `Info.plist` (authoritative), `project.yml`, and any version mirror (e.g. `download.astro` if it pins a version). No DMG is cut this phase.
- The phase retrospective is written.

## Red

- `Red: skip` — doc-only and version-metadata changes (branch touches only `.md`, `.json`, `.plist`, `.yml`, `.astro`). No automated test; human review at the PR is the gate.

## Green

- Update the docs listed above.
- Bump the version constant in all mirrors per the macOS release ritual (Info.plist authoritative).
- Write `docs/product/retrospectives/phase-14-per-platform-pet-identity-retrospective.md` using the `soa-write-retrospective` skill for structure.

## Refactor

- Sweep for stale references to `config.pet` / single-global-pet language across README and onboarding docs.

## Review Focus

- The `config.pet` breaking change is clearly documented for CLI users.
- Version bump is consistent across all mirrors (no drift between `Info.plist`, `project.yml`, and site).
- Retrospective captures the durable learning: second config contract, the Minimalist render path Phase 15 reuses, transient-subagent behavior, and the upstream SoA attribution dependency.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
