# P8.02 Bundle-first resolution + absolute hook path

Size: 3 points
Type: feat
Scope: hooks
Red: required

## Outcome

- When running as a compiled bundled binary, `installHooks` writes the **absolute path** to the sibling `codogotchi-hook` (resolved from `process.execPath`'s directory) into every platform surface (Claude `settings.json`, Codex `hooks.json`, Codex TOML) instead of the bare `codogotchi-hook` name.
- In a dev build (no compiled bundle), install falls back to the bare `codogotchi-hook` name (current behavior) — preserved for `bun` development.
- Swift `defaultRunner` (`HookStatusClient`) resolves the `codogotchi` binary from `Bundle.main` `Contents/Resources/` first, falling back to PATH (`/usr/bin/env`) only when the bundled copy is absent (dev).
- Re-running install remains idempotent: the absolute path replaces any prior codogotchi matcher (bare or absolute) with no duplicate entries.

## Red

- Test `installHooks` writes the resolved absolute `codogotchi-hook` path when an exec path is provided, and the bare name when not (dev fallback).
- Test idempotency: installing twice (bare→absolute, or absolute→absolute) leaves exactly one codogotchi matcher per event with the latest path.
- Swift: test `defaultRunner` (or its resolution helper) prefers a bundled Resources path over PATH when the bundled file exists, and falls back otherwise.
- Run the suite; confirm the new tests fail. Commit `[red]`.

## Green

- Parameterize `CODOGOTCHI_COMMAND` in `hooks.ts`: compute the command string from `process.execPath` sibling resolution when the process is a compiled binary; bare name otherwise. Thread it through the Claude matcher, Codex TOML (`command = …`), and Codex `hooks.json` writers.
- Add a small resolution helper in Swift that returns the bundled binary URL when present, else nil; wire `defaultRunner` to use it.

## Refactor

- Centralize the hook-command-path resolution in one function (avoid the three writers each computing it).

## Review Focus

- **Both sides of the boundary:** the path `installHooks` writes is the path the agent actually spawns — verify against a real platform JSON, not just the unit.
- Edge case: moving/deleting the `.app` orphans the absolute path (the hook command goes missing) — confirm the agent-side failure is graceful and that Update hooks (P8.04) re-writes the path. Note the behavior; full handling is the lockstep ticket.
- Dev-vs-bundle branching: ensure `bun` development still works (bare name + PATH).
- That idempotent re-install converges bare-name installs onto the absolute path.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `installHooks` wrote the bare `codogotchi-hook` name into the Claude/Codex surfaces even when given a bundled `execPath` whose sibling binary existed; the idempotency-convergence assertion also failed because the Claude dedup filter matched on exact `=== "codogotchi-hook"` rather than the substring.
Why this path: binary self-location via `process.execPath` keeps the app from having to pass the path in, and works because both binaries sit in the same Resources dir. Bundle-vs-dev is discriminated by an on-disk check for the sibling `codogotchi-hook` (present only in the compiled `.app`), so callers pass `process.execPath` unconditionally and dev `bun` runs fall back to the bare name + PATH automatically.
Resolution centralized in one `resolveHookCommand(execPath?)` helper; the three writers (Claude matcher, Codex TOML, Codex hooks.json) each receive the resolved string. Claude dedup now matches on the `codogotchi-hook` substring (via `isCodogotchiCommand`) so a prior bare-name install converges onto the absolute path with exactly one matcher per event.
Swift: added `HookStatusClient.resolveRunnerLaunch(argv:resourceURL:fileExists:)` (injectable for tests) that prefers `Bundle.main.resourceURL/codogotchi` when it exists on disk (launched directly, head consumed) and falls back to `/usr/bin/env <argv...>` otherwise; `defaultRunner` delegates to it.
Alternative considered: app passes `--hook-path <abs>` to `hooks install` — more surface, rejected in favor of self-location.
Scope note: Cursor (`installCursorHooks`) still writes the bare name — the ticket Outcome enumerates only the three Claude/Codex surfaces, so cursor bundle-path threading is intentionally out of scope here.
Deferred: orphaned-path recovery UX (moving/deleting the `.app` orphans the absolute path; the hook command then goes missing and the agent-side failure is silent/graceful — no crash, the event just isn't recorded). Update-hooks re-write + the lockstep banner (P8.04/P8.05) is where that path gets re-healed.
Contract note: any resolved absolute hook path still ends in `codogotchi-hook`, so `isCodogotchiCommand` substring detection (used for dedup and `hooksStatus` installed-detection) keeps working for both bare and absolute forms.
