# P4.09 Retrospective + doc sweep

Size: 1 point
Type: docs
Scope: product
Red: skip

## Outcome

- `docs/product/retrospectives/phase-04-floating-pet-retrospective.md` exists and records what shipped, pain points, surprises, and follow-up lessons.
- `docs/product/plans/phase-04-floating-pet.md` delivery status reflects the final shipped/decomposed state.
- README and app-local docs describe Codogotchi as a menu bar plus floating pet app, not a menu-bar-only app.
- Any stale Phase 03 references that call floating pet a future Phase 04 deferral are either updated or left with clear historical context.
- Deferred HP hearts, XP bar, stage indicator, focus-aware visibility, catalog, and distribution polish remain clearly deferred.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**

## Green

- Write the Phase 04 retrospective.
- Update README and app docs for the renamed Codogotchi app and floating pet workflow.
- Update plan status to match reality.
- Sweep only docs directly touched by Phase 04 naming/surface changes.

## Refactor

- Keep this a scoped doc sweep, not a full repo documentation rewrite.
- Do not rewrite historical phase documents except to add clear as-shipped context where stale forward references would mislead future planning.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Retrospective is honest about SpriteKit/AppKit tradeoffs and visual validation results.
- Docs accurately describe what shipped and what remains deferred.
- No public-launch language sneaks into private Phase 04 docs.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
