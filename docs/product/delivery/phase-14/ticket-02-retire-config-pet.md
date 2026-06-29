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

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
