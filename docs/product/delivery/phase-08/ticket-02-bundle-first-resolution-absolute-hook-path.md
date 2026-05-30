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

Red first: [what test failed first]
Why this path: binary self-location via `process.execPath` keeps the app from having to pass the path in, and works because both binaries sit in the same Resources dir.
Alternative considered: app passes `--hook-path <abs>` to `hooks install` — more surface, rejected in favor of self-location.
Deferred: orphaned-path recovery UX (lockstep banner, P8.05).
Contract note:
