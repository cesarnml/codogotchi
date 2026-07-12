# P6.01 Script Rename, Migration Runner, and Reviews Path Migration

Size: 3 points
Type: refactor
Scope: soa-sync

## Outcome

- `scripts/soa-sync.sh` exists; `scripts/sync-skills.sh` is removed; `package.json` `sync` script invokes `soa-sync.sh`
- `soa-sync.sh` reads `.soa-sync-version` (defaults to `0` if absent), runs `apply_migrations()` from current version up to `SOA_TARGET_VERSION`, writes the new version back
- Source-repo mode (`IS_SOURCE_REPO=true`) skips migration logic entirely
- `run_migration_1()` moves `.agents/delivery/*/reviews/` → `docs/product/delivery/*/reviews/` for all existing phases; idempotent (no-op if source already absent)
- All path references to `.agents/delivery/*/reviews/` updated: orchestrator script, `closeout-stack` skill, `son-of-anton-ethos` skill, `delivery-orchestrator.md`
- Delivery ticket template (`docs/template/templates/ticket.template.md`) updated with checklist item: bump `SOA_TARGET_VERSION` and add a migration function when moving tracked files
- Re-running `bun run sync` when `.soa-sync-version` already equals `SOA_TARGET_VERSION` produces no file mutations

## Red

- Write a Bun integration test in `tools/delivery/test/p6-01.test.ts`
- Fixture: `mktemp -d`, `git init`, create source-repo layout with `.agents/delivery/phase-XX/reviews/stub.md`
- Run `soa-sync.sh` against the fixture
- Assert: `.soa-sync-version` exists and contains `1`; `docs/product/delivery/phase-XX/reviews/stub.md` exists; `.agents/delivery/phase-XX/reviews/` is gone
- Assert idempotency: run `soa-sync.sh` again; no file mutations (compare checksums or mtimes before/after)
- Confirm the test fails before any implementation
- Commit with suffix `[red]`: `refactor(soa-sync): migration runner and reviews path migration [red]`

## Green

- Rename `scripts/sync-skills.sh` → `scripts/soa-sync.sh` (preserve all existing logic)
- Update `package.json` `sync` script path
- Add to `soa-sync.sh`:
  - `SOA_TARGET_VERSION=1` constant
  - `.soa-sync-version` read at startup (default `0`); write at end of `apply_migrations()`
  - `apply_migrations()`: loop from `(current + 1)` to `SOA_TARGET_VERSION`, call `run_migration_N()`
  - `IS_SOURCE_REPO` guard: skip `apply_migrations()` entirely in source-repo mode
  - `run_migration_1()`: `git mv` each `.agents/delivery/*/reviews/` → `docs/product/delivery/*/reviews/`; guard with `[ -d ]` for idempotency
- Update all `.agents/delivery/*/reviews/` references across orchestrator script, closeout-stack skill, son-of-anton-ethos skill, delivery-orchestrator.md
- Update `docs/template/templates/ticket.template.md`: add checklist item under `## Refactor` or a new `## Migration` section noting: bump `SOA_TARGET_VERSION` and add `run_migration_N()` when moving tracked files
- Commit with suffix `[green]`: `refactor(soa-sync): migration runner and reviews path migration [green]`

## Refactor

- Extract version read/write into a small helper function if the inline logic is more than 5 lines
- Only refactor what you touched

## Review Focus

- `IS_SOURCE_REPO` guard: confirm source repo never has its reviews moved by `run_migration_1()`
- Idempotency: second run must not error when source path is already absent
- All four reference sites updated (orchestrator, closeout-stack, son-of-anton-ethos, delivery-orchestrator.md) — check both sides of each path boundary
- `SOA_TARGET_VERSION` constant is the single source of truth; no hardcoded `1` elsewhere in the migration runner

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `.soa-sync-version` does not exist; reviews dirs are still under `.agents/delivery/`
Why this path: bundling rename + runner + migration_1 makes the migration contract land atomically — a runner without a migration is untestable
Alternative considered: separate rename ticket — rejected because the rename alone carries no substance and the runner is incomplete without migration_1
Deferred: consumer-side migration logic at `SOA_TARGET_VERSION=1` is a no-op by design; documented in product plan
Contract note: none

Implementation notes:

- `son-of-anton-ethos` SKILL.md had no `.agents/delivery/*/reviews` references; Review Focus listed it but no change was needed — confirmed by grep
- `orchestrator.test.ts` assertion for `createOptions()` output updated alongside `planning.ts` change to keep CI green (this was not called out explicitly in the ticket but was a necessary companion change)
- `cspell.json` extended with `idempotently` and `relinks` — both introduced by this ticket
- `soa-sync.sh` executable bit was dropped during initial write and restored in a `[post-verify]` commit
