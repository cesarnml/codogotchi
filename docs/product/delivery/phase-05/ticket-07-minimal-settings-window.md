# P5.07 Minimal Settings window

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

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
