# Phase 05: Lite Install And Onboarding

**Delivery status:** Product plan approved (2026-05-27). App Store distribution is explicitly non-blocking for Phase 05 exit.

## TL;DR

**Goal:** Make Codogotchi a standalone macOS desktop pet that works immediately after **local install** (Xcode build, signed `.app`, or equivalent dev distribution)—hooks, bundled pet, honest platform copy—without requiring Convex enrollment or Terminal for the default path.

**Ships:**

- App-first Lite onboarding: first-run sheet (hooks explained, consent, backup-then-install) plus a minimal Settings window (Hooks, Pet, Alive stub).
- CLI split: `codogotchi setup` (Lite) and `codogotchi rpg` (opt-in RPG enrollment); `features.rpg_enabled` defaults false for greenfield, true after `rpg`.
- Canonical `~/.codogotchi/` with bundled **Maew** assets; no runtime dependency on `~/.codex/pets/*`.
- Plain-language documentation that Cursor may animate via the **Claude third-party hooks bridge** until Phase 06.

**Defers:**

- **App Store submission**, Apple Developer Program enrollment, store listing, and review-driven packaging (later phase when the product is viable—not a Phase 05 gate).
- Native Cursor / VS Code / Antigravity hook installers and truthful `source_origin` (Phase 06).
- Full in-app RPG enrollment UI and multi-tab Settings (Phase 10).
- Attention tray, signal honesty, HUD, health, loot (Phase 06+ / Phase 08+).

---

Codogotchi is a `state.json` visualizer: the macOS app renders local state; the hook binary writes it. Phase 01 coupled everything to `codogotchi setup` (handle, Convex, GitHub, WakaTime). Phase 05 flips the product default: **Lite is the product**, **Alive (RPG) is opt-in**. **App-first** means the macOS app owns onboarding—not that Phase 05 requires App Store approval. The operator is a **single developer** until stated otherwise—no backward-compatibility code paths or generic migration UX; greenfield defaults plus a **final ticket** that updates the developer’s own config to the new schema with `rpg_enabled: true`. Working target: **Phases 05–14 by 2026-06-30**; App Store registration waits until the stack is product-ready.

## Phase Goal

This phase should leave the product in a state where:

- After **local install** (documented build/run path—e.g. Release build from Xcode, copy to `/Applications`, or project runbook), launch shows a working pet (bundled Maew) without Terminal or Convex.
- First-run onboarding explains hooks, asks consent, **backs up existing hook JSON before writing**, and surfaces honest per-platform status until events fire.
- A developer with an existing RPG setup remains on RPG after phase close (manual config ticket), while the documented greenfield path stays Lite.

## Committed Scope

### App-First Onboarding (Menubar Sheet)

- On first launch, show a **menubar-attached onboarding sheet** (not a full Settings product) that:
  - States that animation is driven by agent hooks (text files under the user’s home directory).
  - Detects which platforms are present on disk (Codex, Claude Code, Cursor, VS Code, Antigravity) and labels which are **installable in this phase** vs deferred.
  - Uses **consent-first** hook install: explain what will be written, then **Install hooks**—no silent overwrite of user hook config.
  - **Backs up** existing Codex / Claude Code hook config (timestamped copy or sidecar) immediately before inserting Codogotchi entries.
- Degraded mode when hooks are missing or not firing:
  - Pet still renders (bundled assets + demo mode).
  - Persistent **Hooks not active** status until at least one hook event is observed, with a clear next action.

### Minimal Settings Window

A small Settings window (expanded in Phase 10), not a substitute for first-run onboarding:

- **Hooks:** per-platform status (`not installed | installed | firing recently | unknown`), install/uninstall for supported platforms, last event time and `source_origin` when available.
- **Pet:** select active pet from `~/.codogotchi/pets/`; optional import/copy from `~/.codex/pets/*` into the canonical store (no live-read from Codex at runtime).
- **Alive (RPG):** **stub only**—what RPG unlocks and that enrollment is `codogotchi rpg` today; full in-app enroll deferred to Phase 10.

### Hook Install Scope (Phase 05)

Reliable installers in this phase:

- Codex (`~/.codex/hooks.json` and related).
- Claude Code (`~/.claude/settings.json`).

**Cursor (documentation, not native install):** Onboarding, README, and runbook must state clearly:

- Cursor may animate the pet when **Settings → Features → Third-party skills** is enabled and Claude-compat hooks list `codogotchi-hook`.
- Transition logs may show `source_origin: claude_code` and Cursor tool names (`Shell`, `Grep`, …)—that is the **bridge**, not proof of a native Cursor hooks file.
- Native `~/.cursor/hooks.json` install and honest `source_origin: cursor` → Phase 06.

### CLI Product Surface

| Command | Role |
| --- | --- |
| `codogotchi setup` | **Lite:** install Codex + Claude Code hooks, seed minimal `~/.codogotchi/config.json` with `features.rpg_enabled: false`, optional pet id (default Maew). No required handle or Convex URL. |
| `codogotchi rpg` | **Alive:** current interactive enrollment (handle, Convex, optional GitHub/WakaTime, first sync), sets `features.rpg_enabled: true`. |

- RPG commands (`sync`, `loot`, etc.) refuse with a clear message when `rpg_enabled === false`, pointing to `codogotchi rpg` or the Settings stub.
- Remove `CODOGOTCHI_CONVEX_URL` from hook shell commands unless a later feature needs it.
- CLI is **developer convenience**; App-first onboarding is the exit-condition hero path.

### Bundled Pet + Canonical Store

- Ship **Maew** as the default bundled pet (`pet.json` + codogotchi spritesheet) and seed `~/.codogotchi/pets/maew/` on first run when no loadable pet exists.
- App must render without `~/.codex/pets/*`.
- Codex-format pets remain an optional import source into `~/.codogotchi/pets/<id>/`.

### Operator Migration (Single User)

- **No** backward-compatibility branches for legacy config shapes in product code.
- **No** generic “migration wizard” for arbitrary users.
- **Final Phase 05 ticket:** update the developer’s existing `~/.codogotchi/config.json` to the new schema with **`features.rpg_enabled: true`** and any required fields—preserving current RPG behavior post-landing.
- Greenfield / “Reset to Lite defaults” remains available for testing; not applied to the operator config automatically.

## Explicit Deferrals

- **Mac App Store distribution:** Apple Developer Program account, app signing for store, notarization for store submission, App Store Connect metadata, and review. Phase 05 only requires a reproducible **developer install** path documented in README/runbook. Store readiness is a later milestone (after Phases 05–14 land on the 2026-06-30 working deadline).
- Native Cursor, VS Code, and Antigravity hook installers; tool-alias tables and attribution fixes (Phase 06).
- Full Settings tabs (General, Health, Loot, Developer depth) and in-app RPG enrollment flow (Phase 10).
- Attention bubble, tray, TTL, signal honesty (`tool.command`, `work_mode`, origin fixes).
- Convex schema changes; XP/HP/loot HUD; premium gating; equip rendering (Phase 08+).

## Exit Condition

Phase 05 is done when a **clean machine** (or fresh macOS user account) can:

1. Install and launch Codogotchi via the **documented local path** (not App Store)—e.g. build Release from Xcode, install the `.app` to `/Applications` (or run from DerivedData per runbook), open once without prior `~/.codogotchi/` config.
2. See Maew render immediately from bundled assets.
3. Complete first-run onboarding (sheet): understand hooks, consent, backup-then-install for Codex and/or Claude Code.
4. Install hooks from minimal Settings if needed; observe the pet react to real events with status **firing recently**.
5. Read in-app or README copy that explains **Cursor-via-Claude-bridge** behavior until Phase 06.

And when the **operator** can:

6. Run `codogotchi setup` / `codogotchi rpg` as documented without `setup` implying RPG enrollment.
7. Continue daily use with **`rpg_enabled: true`** after the final config ticket (no silent downgrade to Lite).

## Retrospective

`required` — Phase 05 changes the primary onboarding boundary (CLI-first → App-first) and will surface durable learnings about hook install consent, backup/restore, and cross-platform copy honesty.
