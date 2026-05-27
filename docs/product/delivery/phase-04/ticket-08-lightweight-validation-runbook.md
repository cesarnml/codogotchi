# P4.08 Lightweight validation runbook

Size: 1 point
Type: docs
Scope: runbooks
Red: skip

## Outcome

- `docs/runbooks/phase-04-validation.md` exists.
- The runbook covers launching Codogotchi, showing/hiding the floating pet, dragging, resizing to min/max, quit/relaunch persistence, display-change fallback, and demo/live state agreement.
- The runbook explicitly says screenshots are optional, not mandatory.
- The runbook gives the owner a short checklist suitable for one local validation session.
- The runbook does not add HP, XP, stage, loot, focus-aware, distribution, or public-launch validation.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**

## Green

- Write `docs/runbooks/phase-04-validation.md`.
- Include prerequisites for local dev build and pet assets.
- Include a short checklist for show/hide, drag, resize, persistence, display fallback, and state sync.
- Include optional evidence suggestions without requiring screenshots.

## Refactor

- Keep the runbook operational and short.
- Link to existing README/dev-build instructions rather than duplicating every launch detail.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- The runbook matches the implemented Phase 04 behavior.
- It remains lightweight.
- It does not imply deferred features shipped.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
