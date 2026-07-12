# P18.01 Config schema and update migration

Size: 3 points
Type: feat
Scope: delivery-config
Red: required

## Outcome

- `orchestrator.config.json` requires non-blank string values for `deliveryBaseBranch` and `closeoutBranch`.
- Resolved orchestrator config exposes `defaultBranch`, `deliveryBaseBranch`, and `closeoutBranch` as separate fields.
- Source-repo config examples and newly scaffolded consumer configs include all three branch roles.
- Consumer `/soa update` / sync migration adds missing `deliveryBaseBranch` and `closeoutBranch` from the existing `defaultBranch` value.
- Migration falls back to `main` only when the existing config has no usable `defaultBranch`.
- Migration is idempotent and preserves valid existing explicit `deliveryBaseBranch` / `closeoutBranch` values.

## Red

- Write failing config tests that load configs missing `deliveryBaseBranch` and `closeoutBranch` and expect clear validation errors.
- Write failing migration coverage showing a config with `defaultBranch: "master"` receives `"deliveryBaseBranch": "master"` and `"closeoutBranch": "master"`.
- Write failing migration coverage showing a config with no `defaultBranch` receives both new fields as `"main"`.
- Run the test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P18.01): require branch role config and migration [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Add `deliveryBaseBranch` and `closeoutBranch` to config types, parsing, validation, and resolved config.
- Update `scripts/soa-sync.sh` target version and add an idempotent migration that rewrites `orchestrator.config.json` using a structured JSON tool when available.
- Update scaffolded `orchestrator.config.json` defaults to include all branch-role fields.
- Keep `defaultBranch` as repo-primary branch only.

## Refactor

- Centralize repeated non-blank branch field validation if it keeps config parsing easier to read.
- Keep migration logic shell-compatible and focused on this config rewrite.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Migration preserves consumer intent for `defaultBranch: "master"` or any other non-blank existing value.
- Missing fields fail clearly after migration has had a chance to run in consumer repos.
- `closeoutBranch` is required; no runtime fallback to `deliveryBaseBranch` remains.
- Config defaults in docs, source config, and sync scaffold agree.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: config validation and migration tests should fail before implementation.
Why this path: required fields make branch roles explicit while migration preserves current consumer behavior.
Alternative considered: defaulting `deliveryBaseBranch` or `closeoutBranch` at runtime was rejected because it would preserve ambiguous branch-role semantics.
Deferred: no per-phase branch override migration.
Contract note: none.

Implementation note: sync migration v2 uses Node to parse and rewrite `orchestrator.config.json` structurally, preserving existing explicit `deliveryBaseBranch` / `closeoutBranch` values and deriving missing branch roles from `defaultBranch` or `main`. Existing config-validation tests now include valid branch-role fields when targeting unrelated validation so missing-field errors stay intentional.
