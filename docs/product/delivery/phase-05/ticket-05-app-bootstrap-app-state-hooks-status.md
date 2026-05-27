# P5.05 [App bootstrap + app-state + `hooks status`]

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

Red first: AppBootstrapTests + AppStateTests for new optional fields driven before any Sources changed.

Why this path: `ConfigBootstrap` is a single-purpose helper that owns the missing-config write; `HookStatusClient` separates subprocess concerns from snapshot parsing via an injectable `runner` so unit tests stay hermetic; `HooksStatusSnapshot` is Codable so the cached snapshot serializes through the existing `AppStateStore` snake-case path without a parallel persistence layer.

Alternative considered: extending `PetConfig` with a "write minimal" path or co-locating subprocess + parse in MenubarApp. Rejected — the ticket's Outcome explicitly asks for a thin client wrapper and a bootstrap surface that can be reused by P5.06 onboarding without dragging menubar lifecycle in.

Deferred: surfacing subprocess failures into onboarding UI (P5.06); enriching the `hooks not active` predicate with a configurable freshness window beyond the CLI-provided `firing_recently` boolean (currently piggybacks on the CLI status contract — firing_recently is the source of truth, `last_event_at` is metadata for UI).

Contract note: `Hooks not active` ≡ "no platform with `installed && firing_recently`". `lastHookActivityAt` caches the latest `last_event_at` seen across platforms so the UI can age out a stale CTA on its own clock if the CLI hasn't been re-run. App-state schema_version unchanged (still 1) — the three new fields are additive optionals; older readers ignore them and pre-existing files load fine because the keys are absent and default to nil. `CODOGOTCHI_HOME` resolution is preserved through `PetConfig.configURL()` and `AppStateStore.appStateURL()`; pet paths already honor it via `CodexPet`/`CodogotchiPet`.
