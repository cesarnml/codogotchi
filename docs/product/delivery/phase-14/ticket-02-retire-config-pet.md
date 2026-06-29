# P14.02 CLI: retire config.pet

Size: 2 points
Type: refactor
Scope: cli
Red: required

## Outcome

- `pet` is removed from the config Zod schema (`configBaseSchema`), from `SETTABLE_TOP_LEVEL`, and from the `config set` / `config get` allow-lists (`TOP_REQUIRED_STRING_KEYS`, `resolveConfigPath`).
- `codogotchi config set pet <name>` now exits non-zero with an "unknown key" error (documented breaking change).
- `codogotchi setup` no longer seeds `pet: "maew"` (both Lite and RPG setup paths).
- An existing on-disk config that still contains a `pet` key is not invalidated — `config set <other-key>` and `config list` continue to succeed without throwing on the leftover key, and do not silently strip it out from under a not-yet-migrated app.

## Red

- Update CLI tests to assert: `config set pet maew` returns a non-zero/`ConfigCommandError`; `setup` writes a config object with no `pet` key; a config file containing `pet` still parses and `config set handle …` succeeds.
- Run `bun run test` (cli/contracts) and confirm the new assertions fail.
- Commit with suffix `[red]`: `test(cli): retire config.pet [red]`.
- Do not write any implementation until this commit exists on the branch.

## Green

- Remove `pet` from `configBaseSchema` in `packages/contracts/src/config.ts`, from `SETTABLE_TOP_LEVEL`, and from `resolveConfigPath`.
- Remove `"pet"` from `TOP_REQUIRED_STRING_KEYS` in `config-command.ts`.
- Remove the `pet: "maew"` seeds in `setup.ts` (both call sites).
- Ensure the config read-merge-write path preserves unknown on-disk keys (do not Zod-strip `pet` out of an existing file on an unrelated `config set`). If `readConfig`/`writeConfig` currently re-serializes the Zod-parsed object, switch the write to merge over the raw parsed JSON so a leftover `pet` survives until the app migrates it.

## Refactor

- Only touch the config-selection surface. Leave RPG/health keys and the Lite/RPG union otherwise intact.

## Review Focus

- **Migration-ordering safety:** the central risk is a CLI write stripping a user's `pet` before the Swift seed (P14.03) runs, silently resetting their default pet to Maew. Verify the write path preserves the leftover `pet` key on disk.
- Confirm `config set pet` failing is intentional and surfaced clearly, not a generic crash.
- This is a breaking change — README/CLI-help updates land in P14.09, but flag any user-facing help string in this PR that still advertises `pet`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `config set pet maew` resolving instead of throwing; `setup` seeding `pet: "maew"` in the written config.

Why this path: `readRawConfig` + shallow-merge in `writeConfig(rawBase?)` is the smallest safe path. It reads the raw JSON once in parallel with the Zod parse, then spreads `{...rawBase, ...zodShape}` before writing so any top-level unknown key (including a leftover `pet`) survives an unrelated set. No deep-merge needed since nested `features`/`health` objects are fully owned by the schema.

Alternative considered: storing the raw JSON inside `readConfig`'s return value (a tuple `[CodogotchiConfig, Record<string, unknown>]`). Rejected — it changes every call site that only needs the validated shape, and the raw-only read stays isolated to `configSet`.

Deferred: `configGet pet` (currently throws "Unknown config key") is intentionally left — users who have `pet` on disk cannot read it via CLI. The Swift migration (P14.03) owns actual migration. README/CLI-help updates land in P14.09.

Contract note: no deviations from ticket metadata.
