# P4.02 Floating app-state store + frame policy

Size: 3 points
Type: feat
Scope: app-state
Red: required

## Outcome

- `~/.codogotchi/app-state.json` is the renderer-local state file for floating visibility, position, and size.
- The app-state reader/writer supports `CODOGOTCHI_HOME` for test isolation, matching existing config/test conventions.
- Missing or malformed app-state file falls back to a visible default: floating pet enabled, bottom-right safe frame, default scale.
- Frame policy defines minimum size, maximum size, default size, and safe visible clamping.
- Saved frame is clamped to the current visible screen area on startup.
- Display-change clamping logic is implemented as testable frame math independent of AppKit window lifecycle.
- `config.json` remains untouched for renderer placement state.

## Red

- Write tests for default app-state values when `app-state.json` is missing.
- Write tests for malformed app-state fallback.
- Write tests that valid visibility, position, and size round-trip through the app-state store.
- Write tests that off-screen or oversized saved frames clamp into a supplied visible screen rect.
- Write a test proving the app-state path uses `CODOGOTCHI_HOME`.
- Run `bun run mac:test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P4.02): floating app-state defaults and clamping [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add an app-state model with explicit fields for floating visibility, origin, width/height or scale, and schema/version if useful for local migration.
- Add load/save helpers rooted at `~/.codogotchi/app-state.json`.
- Add pure frame policy helpers for min/max/default sizing and visible-frame clamping.
- Treat malformed JSON as fallback, not a launch failure.
- Keep writes atomic enough for a local app state file.

## Refactor

- Keep this ticket UI-free. No `NSPanel`, no SpriteKit view, no menu toggle yet.
- Keep frame math pure and unit-testable so display-change behavior in later tickets does not require a window server in tests.
- Reuse existing environment-path patterns from `PetConfig` where they fit.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- App-state is separate from product config and secrets.
- Off-screen fallback is deterministic and not tied to a specific developer display size.
- Corrupt state cannot make the app fail to launch.
- Tests cover the frame-clamping edge cases before UI uses the helpers.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:

Implementation:
Why this path: added a UI-free `AppStateStore` plus `FloatingFramePolicy` so later panel/display-change work can reuse the same persistence and clamping behavior without depending on AppKit window lifecycle.
Alternative considered: storing floating placement in `config.json`, rejected to keep renderer placement separate from user/product config and secrets.
Deferred: display-change event wiring remains for the floating panel ticket; this ticket only supplies the pure frame math and startup load clamp.
Contract note: `~/.codogotchi/app-state.json` and `$CODOGOTCHI_HOME/app-state.json` are the only app-state locations touched by this ticket.
