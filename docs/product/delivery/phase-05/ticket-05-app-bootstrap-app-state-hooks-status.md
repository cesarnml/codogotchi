# P5.05 App bootstrap + app-state + `hooks status`

Size: 2 points
Type: feat
Scope: app-state
Red: required

## Outcome

- Before onboarding: if `~/.codogotchi/config.json` missing, app writes minimal Lite config (new `profile_id`, `pet: "maew"`, `rpg_enabled: false`) — coordinates with P5.04 pet seed order so first frame can show Maew.
- `app-state.json` schema extended (version field bumped if needed) with: `onboarding_completed_at` (optional ISO timestamp), `last_hook_activity_at`, optional cached `hooks_status` snapshot for UI.
- App runs `codogotchi hooks status --json` (or agreed flag) via `Process`, parses JSON, surfaces errors in logs/onboarding later.
- **`Hooks not active`** predicate defined: hooks not installed OR no recent hook-driven activity per status contract (threshold documented in Rationale, e.g. state.json mtime or status field).
- `CODOGOTCHI_HOME` respected for config, app-state, and pet paths in Swift.

## Red

- Write failing tests: bootstrap writes Lite config once; app-state round-trip new fields; mock/subprocess test for status parse if feasible, else pure JSON fixture parse test.
- Commit: `test(P5.05): app bootstrap and hook status integration [red]`.

## Green

- Implement bootstrap in `MenubarApp` or dedicated helper.
- Extend `AppStateStore` model + persistence.
- Add thin `HookStatusClient` wrapper around subprocess.

## Refactor

- Keep subprocess path configurable for tests (inject command or mock client).

## Review Focus

- Bootstrap does not overwrite existing config.
- Subprocess failure does not crash app; leaves CTA state.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
