# P5.03 CLI `setup` / `rpg` split

Size: 3 points
Type: feat
Scope: cli
Red: required

## Outcome

- **`codogotchi setup`:** Lite only — if no config, write minimal Lite config (`profile_id`, `pet: "maew"`, `features.rpg_enabled: false`); then `hooks install`. No handle, Convex, GitHub, or Wakatime prompts. `--force` overwrites config as today.
- **`codogotchi rpg`:** interactive Alive enrollment (current `setup` flow): handle, Convex URL, optional GitHub/Wakatime, first sync; sets `features.rpg_enabled: true` and required RPG fields.
- `USAGE` and `--help` reflect the split.
- `setup` does not enroll in Convex; `rpg` does not silently reinstall hooks unless documented (default: assume hooks already installed; if missing, error points to `hooks install` or app onboarding).
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

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
