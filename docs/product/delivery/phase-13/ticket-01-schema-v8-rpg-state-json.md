# P13.01 CLI: schema v8 + rpg-state.json

Size: 3 points
Type: feat
Scope: cli-schema
Red: required

## Outcome

- `STATE_JSON_SCHEMA_VERSION` is `8` in `packages/contracts/src/state-json.ts`
- `sliceEntrySchema` and `SliceEntry` type carry no RPG fields (`level`, `level_fraction`, `half_hearts`, `active_minutes`, `last_activity_at`, `revive_until` removed)
- `writeSliceAtomic` writes v8 slices containing only activity-signal fields: `schema_version`, `origin`, `session_id`, `activity_state`, `hp_overlay`, `hp`, `updated_at`, `source_event`, `attention` (optional), `tool_command` (optional)
- `rpg-state.json` is written atomically (tmp + rename) inside `withHomeLock`, same critical section as the slice write, on every `runHook` invocation when `rpg_enabled: true`
- On first write of `rpg-state.json` (file absent), the CLI seeds RPG values from: (1) most recent v7 slice in `state.d/` (last-writer-wins on `updated_at`), (2) `state.json` if no v7 slices, (3) safe defaults (level=1, levelFraction=0.0, halfHearts=MAX\_HALF\_HEARTS, activeMinutes=0)
- `bun run ci` passes; no TS type errors

## Red

- Add a test in `packages/contracts/src/slice-entry.test.ts` asserting that a v8 slice payload with RPG fields present fails `sliceEntrySchema` validation (RPG fields are not in the schema)
- Add a test in `packages/cli/src/hook-binary.test.ts` asserting that after `runHook`, a file at `rpg-state.json` exists and contains `level`, `half_hearts` — while the slice file at `state.d/<origin>:<session_id>.json` does NOT contain those fields
- Add a migration seed test: given a pre-existing v7 slice fixture with `half_hearts: 4, level: 3`, when `rpg-state.json` is absent and `runHook` fires, `rpg-state.json` is seeded with `half_hearts: 4, level: 3`
- Run `bun run ci` and confirm the three new tests fail
- Commit: `test(P13.01): slice v8 shape + rpg-state.json separation + migration seed [red]`

## Green

- Bump `STATE_JSON_SCHEMA_VERSION = 8` in `packages/contracts/src/state-json.ts`
- Remove RPG fields from `sliceEntrySchema` in `packages/contracts/src/slice-entry.ts`
- Update `runHook` in `packages/cli/src/hook-binary.ts`:
  - Strip RPG spread from the `slice` object construction
  - After `computeAndPersistV5Fields`, write result to `rpg-state.json` (atomic tmp+rename) inside the existing `withHomeLock` block
  - Before writing, check if `rpg-state.json` is absent; if so, run migration seed scan
- Implement `seedRpgState(home)` helper: reads `state.d/` for last-writer-wins v7 slice (RPG fields optional, fall through to defaults if absent), falls back to `state.json`, falls back to defaults

## Refactor

- Extract `rpgStatePath(home)` helper alongside the existing `statePath` and `sliceDirPath` helpers for consistency
- The migration seed logic is a one-shot path — keep it in `hook-binary.ts`, do not extract to a separate module

## Review Focus

- Confirm `sliceEntrySchema` no longer accepts RPG fields — the schema change must be a hard removal, not marking them `.optional()`
- Confirm `rpg-state.json` is written inside `withHomeLock` — not after it returns
- Confirm the migration seed uses `updated_at` (ISO 8601 wall-clock) as the tiebreak, not filesystem mtime
- Confirm `state.json` fallback reads the same RPG fields as the v7 slice path (they share a shape)
- Confirm `safe defaults` match the Swift-side constants: level=1, levelFraction=0.0, halfHearts=MAX\_HALF\_HEARTS (6), activeMinutes=0
- `slice-entry.ts` `sliceToStateJson` must also drop RPG fields — verify the helper doesn't re-add them

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: soft v7/v8 union in slice schema — rejected; hard break is simpler and the DMG guarantees lockstep.
Deferred: PID field in slice — explicitly deferred to post-v2; TTL is the sole liveness signal.
Contract note:
