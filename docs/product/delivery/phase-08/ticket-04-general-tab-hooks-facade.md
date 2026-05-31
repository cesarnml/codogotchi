# P8.04 General tab — app-owned hooks façade (install/update/remove)

Size: 2 points
Type: feat
Scope: settings
Red: required

## Outcome

- The General tab exposes three actions — **Install hooks**, **Update hooks**, **Remove hooks** — all routed through the app-owned `SettingsController` façade against the bundled binary.
- **Update hooks** is an idempotent re-install: it re-runs `installHooks`, rewriting platform JSON to the current bundle's absolute hook path (no new CLI verb).
- The tab renders a per-platform hooks **status** populated from `HookStatusClient` (`hooks status --json` shape), refreshed after each action.
- A **Copy diagnostics** action copies the status JSON (+ versions) to the clipboard for support.
- Each action reports success/failure inline; failures surface the subprocess stderr.

## Red

- Test `SettingsController` gains an `update` action that invokes the install path and returns nil on success / error string on non-zero exit (mirroring existing `install`/`uninstall`).
- Test the General view-model maps a status snapshot to per-platform rows and refreshes after an action.
- Test Copy diagnostics produces the expected JSON payload.
- Run the suite; confirm failure. Commit `[red]`.

## Green

- Add `runHooksUpdate()` to `SettingsController` (re-runs `hooks install`). Keep `install`/`uninstall` as-is.
- Wire the three buttons + status list + Copy diagnostics in the General tab view; refresh status via `HookStatusClient` after each action.

## Refactor

- Reuse the existing status snapshot rendering; do not duplicate formatting between General and (later) Developer tab — extract a shared formatter if it starts to diverge.

## Review Focus

- That Update genuinely rewrites the path to the current bundle (the lockstep payoff) — not a no-op when already installed.
- Error ergonomics: a failed install/update/remove shows actionable stderr, not a silent failure.
- That the status shown matches `codogotchi hooks status --json` exactly (same shape, app-populated).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: SettingsControllerTests called runHooksUpdate() (non-existent) + GeneralTabViewModelTests referenced GeneralTabViewModel (non-existent) — both compile errors confirmed red.
Why this path: Update = idempotent re-install reuses shipped, tested install logic.
Alternative considered: a distinct `hooks update` CLI verb — unnecessary; install already rewrites.
Deferred: the launch-time mismatch banner (P8.05).
Contract note: diagnosticsJSON builds hooksStatus dict explicitly (not via Codable) to preserve last_event_at/source_origin as null rather than omitting the keys — matches the hooks status --json shape exactly.
Post-subagent patch: applyViewModel(vm) now runs on both success and error branches so status rows refresh after any action outcome, not only on success.
