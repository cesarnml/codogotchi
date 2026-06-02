# P10.03 Contracts — state.json v5, local-RPG config, HUD opt-out

Size: 2 points
Type: feat
Scope: contracts
Red: required

## Outcome

- `STATE_JSON_SCHEMA_VERSION` bumped `4 → 5`. `stateJsonV5Schema` adds: `level: int 1..100`, `level_fraction: number 0..1`, `half_hearts: int 0..6`, `last_activity_at: string datetime | null`.
- `hp` and `hp_overlay` remain (derived) for the existing sprite-overlay path; `parseStateJson` accepts v5 and still accepts ≤4 per the forward-compat policy.
- Decay constants from `@codogotchi/engine` (P10.02) are re-exported from contracts (or defined here and consumed by the engine) so Swift has a single contract source.
- Config: `rpgConfigSchema` no longer requires `convex_http_url`, `handle`, `github_token`, `wakatime_key`, or `health` — a config with `features.rpg_enabled: true` and none of those is valid (local RPG).
- New HUD opt-out flag added under `features` (e.g. `rpg_hud_enabled: boolean`, default `true`) and added to the settable config paths.

## Red

- Failing `vitest`: v5 object with the four new fields parses; a v5 object missing them fails; a local RPG config (`rpg_enabled: true`, no cloud fields) parses; the opt-out flag round-trips through `resolveConfigPath`/settable paths; `half_hearts` out of `0..6` and `level` out of `1..100` rejected.
- Confirm failures; commit `test(P10.03): state v5 + local-rpg config + hud opt-out [red]`.

## Green

- Extend the schemas/version constant and config union minimally to pass. Keep the lite/rpg union coherent.

## Refactor

- Ensure the cloud fields become `.optional()`/`.nullable()` without loosening the lite branch; keep one canonical place for the decay constants.

## Review Focus

- **Forward-compat:** writer always writes current version; confirm a v5 file is rejected by an unmodified ≤4-only reader only where intended, and the bundled reader accepts ≤5.
- That making cloud fields optional does not silently allow a half-configured *sync* state (sync is out of scope; local must be fully valid with zero cloud fields).
- Opt-out flag default `true` so existing installs keep the HUD unless they opt out.

## Rationale

Red first: `STATE_JSON_SCHEMA_VERSION is 5` failed immediately; `parseStateJson` rejected schema_version: 5 with the old max-4 bound.

Why this path: `superRefine` on `stateJsonV1Schema` enforces v5 field presence conditionally — keeps one canonical schema, one parse function, backward compat untouched.

Alternative considered: Separate `stateJsonV4Schema`/`stateJsonV5Schema` union — rejected; adds duplicate field lists and complicates the `StateJsonV1` type consumed everywhere.

Deferred: Conditional "all-or-none" cloud-field validation for the sync path — acceptable because sync is fully disabled in Phase 10 and no code reads those cloud fields. Added `.optional()` to all cloud fields; any future sync rebuild should add a refinement to rpgConfigSchema that requires them together.

Contract note: CLI writer explicitly pins to `schema_version: 4` until P10.05 ships the full v5 writer (level + half_hearts fields). `STATE_JSON_SCHEMA_VERSION = 5` is the reader's forward-compat bound, not the current writer version.

Decay constants: moved from `engine/hearts.ts` to `contracts/decay-constants.ts`; engine imports and re-exports them for backward compat. Swift will import from contracts directly in P10.06.

Subagent-review patches (commit b529d3b):
1. `config-command.ts`: `getDottedValue` and `applyFeaturesValue` extended to handle `features.rpg_hud_enabled` — the flag was missing from the CLI get/set path despite being in the contracts schema.
2. `router.ts`: sync command now guards against local-RPG configs (rpg_enabled: true, no cloud fields) with a clear error. Without this guard, `runSync()` would receive `undefined` for `handle` and `convex_http_url` and fail with a network error rather than a clear message.
Deferred note updated: "sync is fully disabled" was inaccurate — the `sync` command was still accessible; the guard closes that gap.
