# P5.03 [CLI `setup` / `rpg` split]

Size: 3 points
Type: feat
Scope: cli
Red: required

## Outcome

- **`codogotchi setup`:** Lite only — if no config, write minimal Lite config (`profile_id`, `pet: "maew"`, `features.rpg_enabled: false`); then `hooks install`. No handle, Convex, GitHub, or Wakatime prompts. `--force` overwrites config as today.
- **`codogotchi rpg`:** interactive Alive enrollment (current `setup` flow): handle, Convex URL, optional GitHub/Wakatime, first sync; sets `features.rpg_enabled: true` and required RPG fields.
- `USAGE` and `--help` reflect the split.
- `setup` does not enroll in Convex; `rpg` does not reinstall hooks (assumes `setup` already ran). If hooks are missing the user must run `codogotchi hooks install` — missing-hooks error surfacing from `rpg` is deferred to a later ticket.
- Tests cover: greenfield `setup` produces Lite config + calls install; `rpg` on Lite config upgrades shape; `rpg` refuses or prompts when already RPG as appropriate.

## Red

- Write failing tests mirroring P1.12 setup tests but expecting Lite shape and separate `rpg` flow.
- Commit: `test(P5.03): setup lite and rpg enrollment split [red]`.

## Green

- Refactor `packages/cli/src/setup.ts` into Lite + RPG paths; add `rpg.ts` or equivalent.
- Wire `router.ts` for `rpg` command.
- Delegate hook writes to P5.02 `hooks install`.

## Refactor

- Update error messages that say "run setup" to distinguish Lite vs RPG where helpful.

## Review Focus

- No regression path that runs full enrollment on plain `setup`.
- `InstallHooksContext` no longer requires `convex_http_url` for hook install.

## Rationale

Red first: Created `rpg.test.ts` importing non-existent `runRpg` → compile failure confirms RED state.

Why this path: Splitting `runSetup` (Lite, no prompts) from `runRpg` (interactive RPG) removes the only user-facing interactive command from the Lite install path. Lite setup is now purely config-file creation + hook wiring.

Alternative considered: Keeping a single `setup` entry with `--rpg` flag. Rejected — separate subcommands are clearer for users and easier to gate in tests.

Deferred: The `rpg` command does not reinstall hooks (assumes `setup` already ran or app bootstrapped them). If hooks are missing, the user must run `codogotchi hooks install`. Error surfacing for missing hooks is out of scope for P5.03.

Contract note: `InstallHooksContext` drops `convex_http_url` — it was never used in hook wiring (only `ctx.home` was used). This is a clean type reduction with no behavioral change to `installHooks`.
