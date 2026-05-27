# Phase 04 — Floating Pet

> Turn Codogotchi from a menu-bar-only signal into a Codex-style floating desktop companion. Soul: the pet lives on the desktop, can be moved and resized directly, and still reacts to the same agent state as the menu bar pet. Nine tickets, ~20 points, four stage gates.

## Epic

Source product plan: [`docs/product/plans/phase-04-floating-pet.md`](../../plans/phase-04-floating-pet.md).

## Product Contract

When this phase is complete:

- The macOS app is named `Codogotchi`, not `Menubar`, across user-facing app/menu copy and developer project identity.
- The existing LSUIElement menu bar agent remains the single app; the floating pet is a second surface, not a separate binary.
- A transparent float-on-top pet appears at a safe bottom-right default position and can be shown or hidden from the menu bar.
- The floating pet can be dragged by click-holding the floating frame, resized by click-holding the resize affordance, and bounded between documented minimum and maximum sizes.
- Floating visibility, position, and size persist in `~/.codogotchi/app-state.json`, separate from user/product `config.json`.
- Saved placement is clamped to a visible safe frame at startup and after display changes.
- Both the menu bar renderer and floating SpriteKit scene consume the same live/demo activity state stream.
- The reserved Codex rows (`running-right`, `running-left`, `jumping`) are visibly exercised for mouse-reactive feedback where assets support them, with graceful fallback.
- A lightweight Phase 04 validation runbook exists for owner attestation of show/hide, drag, resize, persistence, display fallback, and state sync.

## Grill-Me Decisions Locked

- **AppKit shell + SpriteKit renderer.** The floating shell is AppKit (`NSPanel` or equivalent) because transparency, float level, dragging, resizing, and LSUIElement ownership are AppKit concerns. The floating content is SpriteKit (`SKView` / `SKScene`) because HP hearts, XP bars, stage indicators, particles, loot moments, and layered character UI belong in a scene graph.
- **Rename first.** `Menubar` → `Codogotchi` lands before floating work so project/scheme/product/menu churn does not mix with new SpriteKit behavior.
- **Menu toggle is required.** Phase 04 ships a persisted Show/Hide Floating Pet menu item. The pet is visible when enabled; focus-aware visibility is deferred.
- **Renderer-local app state file.** Floating visibility, position, and size live in `~/.codogotchi/app-state.json`, not `~/.codogotchi/config.json`. Credentials, pet selection, and health knobs stay in config; renderer placement is app state.
- **Minimal display-change safety.** Startup fallback alone is not enough. If displays change and the saved frame becomes invalid, the app relocates the floating pet to a visible safe frame. Per-display preferences and docking policies remain deferred.
- **Lightweight validation runbook.** One checklist document, no mandatory screenshot packet. The owner is visual QA, but the exit condition must still be concrete.
- **Stage gates are markers, not orchestrator stops.** The orchestrator stops at every ticket boundary regardless. Gates below are observation points where exit-condition progress is judgeable.
- **Retrospective:** `required`. Trigger: architecture/process impact plus durable-learning risk. Phase 04 changes the macOS app boundary and establishes the floating scene foundation for later HP/XP/stage UI.

## Ticket Order

1. `P4.01 Codogotchi app identity rename`
2. `P4.02 Floating app-state store + frame policy`
3. `P4.03 SpriteKit floating scene foundation`
4. `P4.04 Floating panel shell + menu toggle`
5. `P4.05 Shared live/demo state fanout`
6. `P4.06 Drag, resize affordance, cursor, persistence`
7. `P4.07 Mouse-reactive reserved Codex rows`
8. `P4.08 Lightweight validation runbook`
9. `P4.09 Retrospective + doc sweep`

## Ticket Files

- `ticket-01-codogotchi-app-identity-rename.md`
- `ticket-02-floating-app-state-store-and-frame-policy.md`
- `ticket-03-spritekit-floating-scene-foundation.md`
- `ticket-04-floating-panel-shell-and-menu-toggle.md`
- `ticket-05-shared-live-demo-state-fanout.md`
- `ticket-06-drag-resize-affordance-cursor-persistence.md`
- `ticket-07-mouse-reactive-reserved-codex-rows.md`
- `ticket-08-lightweight-validation-runbook.md`
- `ticket-09-retrospective-and-doc-sweep.md`

## Exit Condition

All exit conditions from the product plan are demonstrably true:

1. The macOS app launches as Codogotchi and still exposes the menu bar micro-pet.
2. A transparent floating pet can be shown, hidden, dragged, and resized between the documented min/max bounds.
3. Floating visibility, position, and size survive quit/relaunch via `~/.codogotchi/app-state.json`.
4. Invalid saved placement is corrected at startup and after display changes.
5. The floating SpriteKit scene and menu bar renderer agree on the same live or demo activity state.
6. Reserved Codex rows are visibly exercised at least once or gracefully skipped with documented evidence when the active asset lacks them.
7. The lightweight Phase 04 validation runbook exists and can be run by the owner.
8. Focus-aware visibility, HP hearts, XP bars, stage indicators, loot UI, public launch assets, and distribution polish remain absent by design.

## Stage Gates

- **Gate 1 (after P4.02).** The app identity and renderer-local persistence boundary are stable. No floating panel yet.
- **Gate 2 (after P4.05).** The floating pet appears and tracks the same state stream as the menu bar pet.
- **Gate 3 (after P4.07).** Direct manipulation and mouse-reactive reserved rows are complete.
- **Gate 4 (after P4.08).** Lightweight validation checklist exists and Phase 04 can be visually attested.

## CI Baseline

Run `bun run ci:quiet` on `main` before P4.01 starts; record outcome here.

Expected gate:

- `bun run verify:quiet`
- `bun test packages convex`
- `bun run mac:test`

Phase 04 changes the Xcode project/scheme name in P4.01. That ticket must update `package.json` `mac:build`, `mac:test`, `ci`, and `ci:quiet` behavior so subsequent tickets use the renamed scheme/project.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass `bun run ci:quiet` before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Swift behavior tickets require Red first unless ticket metadata says `Red: skip`.
- Docs-only tickets skip Red structurally.
- Swift work is verified locally through `bun run mac:test` / `xcodebuild test`; root `ci` must continue to include macOS tests.
- Subagent review policy from `orchestrator.config.json` is `skip_doc_only`: P4.01 through P4.07 receive subagent review; P4.08 and P4.09 skip when they remain doc-only.

## Explicit Deferrals

- **Focus-aware visibility.** Deferred. The pet is visible when enabled, regardless of frontmost app.
- **HP hearts, XP bar, stage indicator, loot UI, and character sheet.** Deferred. SpriteKit is chosen to support these later, not to ship them now.
- **Autonomous movement and physics.** Deferred. The owner moves and sizes the pet directly.
- **Pet catalog and richer manifest format.** Deferred. Phase 04 uses the existing active pet config and hardcoded row-map precedent.
- **Advanced display management.** Deferred. Only safe visibility fallback ships.
- **Distribution polish.** Deferred. No signed installer, notarization, Sparkle, or launch-at-login implementation.
- **Public launch assets.** Deferred. No marketing GIF or public web tie-in.

## Stop Conditions

- The `Menubar` → `Codogotchi` rename leaves `bun run mac:test` or root `bun run ci:quiet` unable to address the app target/scheme.
- SpriteKit cannot load or animate the existing sliced frame assets without a broad asset-pipeline rewrite. Stop and narrow before replacing loaders.
- The floating panel cannot remain transparent and float-on-top as an LSUIElement-owned surface without major app-lifecycle redesign.
- Display clamping cannot be made deterministic in tests. Stop and extract the frame math before continuing UI work.
- Drag/resize gestures conflict such that resize handle and whole-frame dragging cannot be distinguished reliably.

## Phase Closeout

Retrospective: required
Why: Architecture/process impact (second native app surface, app identity rename, AppKit shell + SpriteKit scene boundary, renderer-local app state) plus durable-learning risk (this scene becomes the future HP/XP/stage surface).
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-04-floating-pet-retrospective.md`
