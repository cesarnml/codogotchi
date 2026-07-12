# P6.02 Retrospective Location Migration

Size: 1 point
Type: refactor
Scope: retrospectives

## Outcome

- `docs/product/retrospectives/` exists and contains all three existing retrospective files (phase-03, phase-04, phase-05), renamed to plan-slug convention
- `notes/public/` contains no `.md` files
- `soa-write-retrospective` skill path reference updated from `notes/public/` → `docs/product/retrospectives/`

## Red

- Write a Bun integration test in `tools/delivery/test/p6-02.test.ts`
- Assert: `docs/product/retrospectives/` directory exists; three retro files are present there; `notes/public/` contains no `.md` files; `soa-write-retrospective` skill file does not reference `notes/public/`
- Confirm the test fails before any implementation (directory absent or retros still in `notes/public/`)
- Commit with suffix `[red]`: `refactor(retrospectives): migrate retros to docs/product/retrospectives [red]`

## Green

- `mkdir -p docs/product/retrospectives/`
- `git mv notes/public/phase-03-orchestrator-ergonomics-retrospective.md docs/product/retrospectives/`
- `git mv notes/public/phase-04-orchestrator-contract-stability-retrospective.md docs/product/retrospectives/`
- `git mv notes/public/phase-05-subagent-review-clarity-and-pr-scope-propagation-retrospective.md docs/product/retrospectives/`
- Update path reference in `soa-write-retrospective` skill (`SKILL.md`) from `notes/public/` → `docs/product/retrospectives/`
- Commit with suffix `[green]`: `refactor(retrospectives): migrate retros to docs/product/retrospectives [green]`

## Refactor

- None

## Review Focus

- Confirm `notes/public/` still exists as an empty directory (do not delete it — other non-retro files may be placed there in the future)
- Confirm skill reference is updated in the correct location (the path string the skill uses when telling Claude where to write the file)
- File names: verify plan-slug convention is preserved exactly as-is (no renaming beyond the directory move)

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `docs/product/retrospectives/` does not exist; retros are in `notes/public/`
Why this path: `docs/product/` is the canonical home for all delivery artifacts; `notes/public/` was a provisional location
Alternative considered: encoding this as `run_migration_2()` in `soa-sync.sh` — rejected because retrospectives are source-repo-only artifacts; there is no consumer-side equivalent and no need for a version-tracked migration
Deferred: none
Contract note: none
