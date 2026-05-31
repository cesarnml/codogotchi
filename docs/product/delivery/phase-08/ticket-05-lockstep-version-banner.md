# P8.05 Lockstep — installedHookVersion + launch detection + banner

Size: 3 points
Type: feat
Scope: app
Red: required

## Outcome

- `app-state.json` gains an `installedHookVersion` field; `APP_STATE_SCHEMA_VERSION` bumps 1→2 with an idempotent migration that defaults the field to `nil` for existing files.
- On Install / Update hooks, the app records the **bundled** hook version (reported by the bundled `codogotchi --version`/generation token) into `installedHookVersion`.
- On launch, when hooks are installed **and** the bundled version differs from `installedHookVersion`, the app shows a **persistent, non-blocking banner** ("Hooks are out of date — Update") that runs the install-API update and clears on success.
- When versions match (or no hooks installed), no banner.
- The app never silently rewrites agent config dirs — the banner requires a user click.

## Red

- Test the needs-update predicate: installed && bundled != recorded → true; equal → false; not installed → false; recorded nil (fresh/migrated) → true only if hooks installed.
- Test the `app-state.json` v1→v2 migration is idempotent and preserves existing fields.
- Test that a successful update writes the bundled version into `installedHookVersion` and the predicate then returns false.
- Run the suite; confirm failure. Commit `[red]`.

## Green

- Add `installedHookVersion` to `FloatingAppState` + bump `APP_STATE_SCHEMA_VERSION`; add the migration in `AppStateStore.load`.
- Record the version in the install/update path (P8.04 façade).
- Add launch-time comparison + a banner view (menubar and/or Settings → General) bound to the predicate.

## Refactor

- Keep the version-compare predicate pure and unit-testable, separate from the banner view.

## Review Focus

- The version token: where the bundled version comes from (binary-reported) and that it actually changes between releases — a constant that never bumps makes the banner dead.
- Migration safety: an old `app-state.json` must not be corrupted or reset (frame/onboarding flags preserved).
- That the banner is persistent (not a one-shot dismissable nag) yet non-blocking, and clears on successful update.
- Consent line: confirm no code path silently rewrites platform JSON on launch.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: compile errors on LockstepPolicy (missing type), FloatingAppState.installedHookVersion (missing field), GeneralTabViewModel.needsBannerUpdate (missing computed property).
Why this path: launch-detect + banner delivers lockstep with consent; cheap delta over the existing button.
Alternative considered: silent auto-upgrade on launch — rejected (invasive writes without consent); post-v1 escalation.
Deferred: silent auto-upgrade; Sparkle.
Contract note: LockstepPolicy guards on bundledVersion == "unknown" — no banner if the binary can't be queried, preventing a false-positive nag on broken installs. recordInstalledHookVersion skips the write for the same reason.
