# P5.07 [Minimal Settings window]

Size: 3 points
Type: feat
Scope: settings
Red: required

## Outcome

- **Settings** window (standard macOS Settings scene or dedicated window) with three sections:
  - **Hooks:** per-platform status from `hooks status`; Install / Uninstall for Codex + Claude only; last event time and `source_origin` when available; Cursor bridge explained inline (link to README).
  - **Pet:** list/select pets under `~/.codogotchi/pets/`; **Import from Codex…** copies `~/.codex/pets/<id>/` → `~/.codogotchi/pets/<id>/` (no runtime read from Codex after import).
  - **Alive (RPG):** stub copy + "Run `codogotchi rpg` in Terminal" — no in-app enroll.
- Settings Install/Uninstall use same `codogotchi hooks` subprocess as onboarding.
- Menu bar exposes Settings entry (replacing or supplementing ad-hoc items as needed).

## Red

- Write failing tests: import copy creates canonical files; settings open does not require RPG config; hook buttons invoke subprocess mock.
- Commit: `test(P5.07): minimal settings hooks and pet import [red]`.

## Green

- Implement Settings UI and wiring to P5.05 status client.
- Implement Codex → canonical copy helper (Swift or shell to CLI — prefer Swift FileManager copy with tests).

## Refactor

- Defer General/Health/Loot/Developer tabs (Phase 10).

## Review Focus

- Import is copy-only; app never loads pet from `~/.codex` at runtime after Phase 05.
- Settings and onboarding share status model (no contradictory labels).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Wrote failing tests for `SettingsController` (install/uninstall subprocess invocation, RPG-independence) and `PetImportHelper` (copy creates canonical files, empty-source returns empty list) before adding any source files. Required an explicit `xcodegen generate` pass to include new test files in the xcodeproj since XcodeGen produces a static file list at generation time, not at build time.

Why this path: `SettingsController` mirrors `OnboardingController`'s runner-injection pattern so the same `HookStatusClient.defaultRunner` works in production and tests can inject a spy. `PetImportHelper` wraps `FileManager.copyItem` with injected roots and `FileManager` for testability.

Alternative considered: Using SwiftUI `Settings {}` scene — deferred because the app is a pure AppKit LSUIElement agent with no scene infrastructure; adding a SwiftUI scene would require `@NSApplicationMain` restructuring. Programmatic `NSPanel` used instead, matching the onboarding pattern already in place.

Deferred: Pet selection UI that actually switches the active pet at runtime (Phase 10). General/Health/Loot/Developer tabs (Phase 10). Cursor native install (Phase 06).

Contract note: Import is copy-only — no runtime read from `~/.codex/pets/` after Phase 05. Settings Install/Uninstall call `codogotchi hooks install|uninstall` subprocess, same as onboarding. Hook status is shared via `updateHookStatus(_:)` push from `MenubarApp.refreshHookStatusCache()`.

Subagent-review patch: `PetImportHelper.importPet` now uses a `.bak` sibling rename before `copyItem` and restores on failure — prevents data-loss if `copyItem` fails after `removeItem` succeeds (spec-permits-real-bug finding).

Advisory observations accepted as deferred or out-of-scope:
- Canonical pet listing in Settings UI deferred to Phase 10 (Full Settings tabs).
- Cursor bridge "link to README" is plain text in the programmatic NSPanel — acceptable for Phase 05; clickable NSAttributedString link is a polish item.
- `SettingsWindowController` wiring coverage is advisory; sub-components are individually tested.
- `handleImportPet` sync on main thread: acceptable tradeoff at Phase 05 sprite sizes.
- Subprocess hang timeout: same pattern as `OnboardingController`; accepted.
