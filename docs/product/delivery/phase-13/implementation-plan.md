# Phase 13 — Per-Platform Multi-Pet & Customization

> Make the Phase 12 `state.d/` refactor visible to users: one floating pet window per active AI platform, RPG state extracted to its own file, a new Settings > Customization tab, and a static Codogotchi identity icon in the menu bar.

## Epic

Product plan: [`docs/product/plans/phase-13-per-platform-multi-pet.md`](../../plans/phase-13-per-platform-multi-pet.md).

## Product contract

When this phase is complete, a user with `claude_code` and `vscode` active simultaneously sees two separate floating pet windows — one per platform — with no configuration required. Opening Settings > Customization lets them collapse any platform into a combined pet or turn it off entirely. All floating windows share identical RPG state sourced from `~/.codogotchi/rpg-state.json`. The menu bar icon is the static Codogotchi app logo (not an animated sprite) with an optional monochrome variant for light/dark system themes. The codebase is tagged v2.0.0; no DMG is cut until ~v2.5 (post Phase 14 per-thread, Phase 15 minimal mode, and upstream SoA session_id fixes).

## Grill-Me decisions locked

- **Schema v8 = hard break, no fallback.** Strip RPG fields from `SliceEntry`; `rpg-state.json` becomes the sole RPG source of truth. CLI and Swift ship atomically via DMG. No dual-write, no soft-upgrade compat path — users install via DMG which guarantees lockstep.
- **No PID liveness.** TTL is the sole liveness signal for slice freshness. PID complexity deferred until user complaints surface a real gap.
- **`FloatingPetWindowPool` owns N windows.** Single object keyed by origin, independently unit-testable. Replaces single `floatingPetController` in `MenubarApp`.
- **Single `LivePollingDriver`, `perPlatform` reducer.** One driver reads all slices, runs `perPlatform`, hands `[origin: StateJsonV1]` to the pool. Existing per-tick `tickForTesting()` seam preserved with updated signature.
- **`rpg-state.json` written inside `withHomeLock`, polled at 1Hz.** No file watcher. Migration seed on first write: scan v7 slices → `state.json` → safe defaults. No RPG progress lost on upgrade from v1.
- **`customization.json` owns all display preferences.** Platform modes, idle-dismiss TTL, and the new `menubar_icon_monochrome` flag all live here.
- **Menubar icon = static Codogotchi app logo.** `MenubarRenderer` no longer drives the menubar image. All animation stays in floating panels. Monochrome toggle in Settings > General.
- **Menu shape: per-active-platform hide toggles.** Collapses to single `Hide Pet` when only one platform is active.
- **v2.0.0 version tag lands in ticket 07.** No DMG cut until v2.5.

## Ticket Order

1. `P13.01 CLI: schema v8 + rpg-state.json`
2. `P13.02 Contracts: customization.json type + Zod schema`
3. `P13.03 Swift: RpgStateReader + EXPECTED_STATE_SCHEMA_VERSION = 8`
4. `P13.04 Swift: FloatingPetWindowPool + updated LivePollingDriver`
5. `P13.05 Swift: CustomizationJsonReader + pool mode routing`
6. `P13.06 Swift: Settings > Customization tab + per-platform menu items`
7. `P13.07 Swift: Static menubar icon + monochrome toggle + v2.0.0 bump`
8. `P13.08 Docs sweep + retrospective`

## Ticket Files

- `ticket-01-schema-v8-rpg-state-json.md`
- `ticket-02-customization-contract.md`
- `ticket-03-swift-rpg-state-reader.md`
- `ticket-04-floating-pet-window-pool.md`
- `ticket-05-customization-json-reader.md`
- `ticket-06-settings-customization-tab.md`
- `ticket-07-static-menubar-icon.md`
- `ticket-08-docs-retrospective.md`

## Dependency Graph

P13.01 → P13.03 → P13.04 → P13.05 → P13.06
P13.02 ──────────────────────────────▶ P13.05
P13.07 (independent, can run in parallel with P13.05–06)
P13.08 (last — depends on all others)

## Exit Condition

A developer opens `claude_code` in one terminal and `vscode` in another. Two separate floating pet windows appear — one per platform — without any configuration. Opening Settings > Customization collapses `vscode` to "combined" and the second window merges into the shared pet. Changing idle-dismiss TTL to 1 minute and leaving both tools idle causes the non-last-active window to dismiss within 60 seconds while the last-active window stays visible. All windows show the same level and HP throughout. The menu bar shows the static Codogotchi girl logo; enabling the monochrome toggle in Settings > General switches it to a template-image variant. The app version reads 2.0.0.

## CI Baseline

> To be recorded at phase start: `bun run ci:quiet` on the SHA where P13.01 branches from main. Record result and failure count here before the first ticket commit.

## Review Rules

- Tickets merge in order per dependency graph. P13.02 may land any time before P13.05.
- P13.07 may proceed in parallel once P13.03 is merged.
- Each ticket PR must pass CI before the next dependent ticket starts.
- All PRs target `main`.
- P13.04 is the behavior-visibility gate: two active slices must produce two floating windows before P13.05 starts.

## Explicit Deferrals

- **Per-thread floating pets (`perThread` reducer, `SessionIdPanel`)** — Phase 14. The `session_id` key in slice filenames is already in place.
- **PID-based liveness detection** — deferred until user complaints surface a real gap; TTL covers the common cases.
- **Per-platform window position persistence** — Phase 13 windows inherit the existing single-window position from `app-state.json`. Per-platform position memory is UX polish deferred post-Phase 13.
- **`gate.json` / `delivery-context.json` session_id support** — upstream SoA change; deferred to the v2.5 release window.
- **Social RPG features, leaderboards, public profiles** — post-v2.
- **Phase 15 minimal mode** (PlatformBadge + AnimationBadge + SessionIdBadge only, no pet or RPG HUD) — Phase 15.

## Stop Conditions

- Multi-window management surfaces an AppKit thread-safety issue not covered by `@MainActor` on `FloatingPetWindowPool` — pause and get input.
- `rpg-state.json` migration seed produces wrong RPG values from a real v7 slice fixture — fix before proceeding to P13.03.
- The `perPlatform` reducer wired to N windows causes a rendering regression on the single-platform case — pause and characterize before continuing.
- Broken CI that cannot be resolved within the ticket scope.

## Phase Closeout

Retrospective: required
Why: first user-facing v2 feature; changes default floating pet behavior for all users; introduces rpg-state.json, customization.json, and FloatingPetWindowPool as durable architectural boundaries that Phase 14+ builds on.
Trigger: developer approval of P13.08 PR merge.
Artifact: `docs/product/retrospectives/phase-13-per-platform-multi-pet-retrospective.md`
