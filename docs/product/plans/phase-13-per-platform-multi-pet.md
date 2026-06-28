# Phase 13: Per-Platform Multi-Pet & Customization

**Delivery status:** Delivered — Phase 13, 2026-06-29 (PRs [#131](https://github.com/cesarnml/codogotchi/pull/131)–[#138](https://github.com/cesarnml/codogotchi/pull/138), app v2.0.0).

## TL;DR

**Goal:** Make the Phase 12 `state.d/` refactor visible to users by spawning one independent floating pet window per active AI platform, with a new Settings > Customization tab for per-platform control.

**Ships:**
- One floating pet window per active platform (claude_code, vscode, codex, cursor, antigravity) by default — no opt-in required
- New `customization.json` config file for per-platform mode settings (own pet / combined / off)
- Settings > Customization tab with per-platform mode pickers and a configurable idle-dismiss TTL
- `rpg-state.json` extracted from `state.d/` slices — RPG values (level, HP, hearts) become global and identical across all pet windows; slices become pure activity-signal files (schema v8)
- PID-based liveness detection in slice files, with staleness TTL as crash fallback
- `perPlatform` reducer wired to render (was unit-tested but unwired after Phase 12)

**Defers:**
- Per-thread (per-`session_id`) floating pets and `SessionIdPanel` → Phase 14
- `perThread` reducer variant → Phase 14
- Social RPG features, leaderboards, public profiles → post-v2

---

Phase 12 delivered the `state.d/<origin>:<session_id>.json` slice directory and the `perPlatform` reducer as a proven-but-unwired foundation. The product is now ready to make that work visible: each active AI platform gets its own floating pet instead of all platforms sharing one. Phase 13 is the first user-facing v2 feature and the first release that makes per-platform state meaningful to users.

## Phase Goal

This phase should leave the product in a state where:

- A user with claude_code and vscode active simultaneously sees two separate floating pet windows — one per platform — with no configuration required
- A user can open Settings > Customization and set any platform to "combined" (contributing to one shared pet) or "off" (invisible to the system entirely)
- A user can configure how long an idle platform's floating pet window lingers before auto-dismissal (1 min / 5 min default / 15 min / 30 min / 1 hr / Never)
- All floating pet windows show identical RPG state (same level, HP, hearts) sourced from a single `rpg-state.json`, never diverging based on which platform was most recently synced
- The `perPlatform` reducer is the live render path; `globalAggregate` remains available only for platforms in "combined" mode

## Committed Scope

### Multi-window floating pet render

- Replace the single `FloatingPetWindowController` with a collection — one controller per active platform in "own pet" mode
- Windows are spawned when a platform's first active slice appears; dismissed when the slice ages past the TTL or liveness check fails
- Liveness: slice files include the writing process's PID; Swift checks `kill(pid, 0)` for immediate death detection; TTL is fallback for crash/pre-PID slices
- "Combined" mode platforms fold into a single shared window (v1 behavior) via `globalAggregate`
- "Off" mode platforms are filtered out before any reducer runs — their slices are invisible to the render pipeline

### RPG state extraction (schema v8)

- Introduce `~/.codogotchi/rpg-state.json` as the single source of truth for global RPG values: `level`, `level_fraction`, `hp`, `half_hearts`, `hp_overlay`, `active_minutes`
- CLI hook writer stops embedding RPG fields in `state.d/` slices; slices carry only activity-signal fields: `activity_state`, `source_event`, `updated_at`, `origin`, `session_id`, `schema_version`, PID
- Swift reads `rpg-state.json` once at startup and on file change; all floating pet windows share this single RPG model
- Schema version bumped to 8; `StateJsonReader` updated accordingly

### Settings > Customization tab

- New `SettingsTab.customization` case added between `pet` and `rpg` in display order
- Per-platform mode picker (own pet / combined / off) for each detected platform
- Idle-dismiss TTL picker: 1 min / 5 min (default) / 15 min / 30 min / 1 hr / Never — matches claude-status-bar UX pattern
- Settings write to `~/.codogotchi/customization.json`; Swift reads on startup and observes file changes
- TTL setting is render-only (never deletes slice files); the most-recently-active pet window is always kept visible regardless of TTL

### `customization.json` contract

- New file: `~/.codogotchi/customization.json` with `schema_version`, `platform_modes` (map of origin → `"own" | "combined" | "off"`), and `idle_dismiss_ttl_seconds` (number, 0 = Never)
- Default state (file absent or platform not listed): `"own"` for all platforms, TTL = 300 (5 min)
- Contracts package updated with TypeScript type and Zod schema for `customization.json`

### CLI updates

- `writeSliceAtomic` updated to include PID and omit RPG fields (schema v8 payload)
- CLI reads and writes `rpg-state.json` during `codogotchi sync` (replaces embedding RPG in slice)

## Explicit Deferrals

- **Per-thread (per-`session_id`) floating pets** — deferred to Phase 14. The data layer (`session_id` in slice filenames) is ready, but the `perThread` reducer, `SessionIdPanel` UI, and per-thread TTL UX are a distinct feature that needs per-platform to be stable first.
- **`SessionIdPanel`** — shows truncated user prompt below PlatformBadge; deferred to Phase 14 with per-thread mode.
- **Windowed position memory per platform** — Phase 13 windows inherit the existing single-window position from `app-state.json`; per-platform position persistence is a UX polish item deferred post-Phase 13.
- **PID-based liveness for non-CLI hooks** (antigravity, vscode shell hooks) — those hooks don't run as a named `claude` process. PID liveness applies to CLI-origin slices; TTL fallback covers the rest. Full liveness parity deferred.

## Exit Condition

A developer can open multiple AI coding tools (e.g. claude_code in one terminal, vscode open) and see separate floating pet windows appear — one per active platform — without any configuration. Opening Settings > Customization lets them collapse any platform into the combined pet or turn it off entirely. Changing the idle-dismiss TTL from 5 minutes to 1 minute and then leaving all tools idle causes all but the most-recently-active pet window to dismiss within 1 minute. All pet windows display the same level and HP throughout.

## Retrospective

`required` — Phase 13 is the first user-facing v2 feature, changes the default floating pet behavior for all users (including the upgrade path from v1), introduces a new config file contract, and makes architectural choices (RPG extraction, PID liveness, customization.json) that directly constrain Phase 14 per-thread design. Durable learning is likely.
