# Phase 04: Floating Pet

**Delivery status:** Delivered 2026-05-26 (9/9 tickets, stacked PRs [#45](https://github.com/cesarnml/codogotchi/pull/45)–[#53](https://github.com/cesarnml/codogotchi/pull/53)). Retrospective: [`docs/product/retrospectives/phase-04-floating-pet-retrospective.md`](../retrospectives/phase-04-floating-pet-retrospective.md). Validation: [`docs/runbooks/phase-04-validation.md`](../../runbooks/phase-04-validation.md).

## TL;DR

**Goal:** Turn Codogotchi from a menu-bar-only signal into a Codex-style floating desktop companion that is draggable, resizable, state-aware, and still anchored by the existing menu bar app.

**Ships:**

- The macOS app identity moves from the Phase 02 placeholder name, `Menubar`, to `Codogotchi` across the user-facing app surface and developer project identity.
- A transparent float-on-top pet window appears alongside the existing menu bar micro-pet, using the active pet selected by `~/.codogotchi/config.json`.
- The floating pet can be dragged by click-holding anywhere on the floating frame except the resize affordance.
- A visible resize affordance on the floating frame supports click-hold resizing between the screenshot-calibrated minimum and maximum sizes, with a resize cursor when macOS allows it.
- The floating pet remembers its last position and size across app restarts, with a safe fallback when the saved frame no longer fits the current display.
- The floating surface renders the same live `state.json` activity stream as the menu bar pet, plus mouse-reactive basics that consume the reserved Codex rows (`running-right`, `running-left`, `jumping`) where the active Codex sheet supports them.

**Defers:**

- Focus-aware visibility that only shows the pet when Codex, Claude Code, Claude Desktop, or related terminal sessions are active.
- HP overlays, ghost/death visuals, mood tints, and social-drama effects.
- Pet catalog, picker UI, multi-pet validation, and richer pet manifest design.
- Autonomous desktop movement, physics, edge snapping, magnetism, and multi-display preference controls beyond safe placement fallback.
- Public launch assets, README GIF marketing, signed installer, notarization, Sparkle, and launch-at-login polish.

---

Phase 02 proved the native macOS anchor: an LSUIElement menu bar app reads `~/.codogotchi/state.json`, renders the pet at menu-bar scale, logs transitions, and survives sleep/wake. Phase 03 completed the visible activity vocabulary by rendering all 15 contract states, added per-pet configuration, and deliberately reserved the Codex `running-right`, `running-left`, and `jumping` rows for a future float-on-top surface. Phase 04 is that surface.

Non-binding notes and drafts remain useful context only. The binding product direction for this phase is: ship the floating pet as the main feature set, make it feel like the Codex desktop pet reference in the supplied screenshots, and keep the scope private and local-first.

## Phase Goal

This phase should leave the product in a state where:

- The owner can run Codogotchi as one macOS agent named `Codogotchi`, with the menu bar micro-pet still present and a separate floating pet visible on the desktop.
- The floating pet feels like a real desktop companion: it is transparent, float-on-top, draggable, resizable between bounded min/max sizes, and not trapped inside a conventional app window.
- Dragging and resizing are direct manipulation gestures: click-hold on the frame moves the pet; click-hold on the resize affordance changes scale.
- The app remembers the owner's chosen location and size after quit/relaunch, without reopening off-screen when displays change.
- The floating surface and menu bar surface agree on the same current activity state from `state.json`.
- The reserved Codex mouse-interaction rows stop being dead contract surface: horizontal movement can use `running-right` / `running-left`, and hover/resize attention can use `jumping` where assets exist.

## Committed Scope

### App Identity

- Rename the macOS app identity from `Menubar` to `Codogotchi` so Phase 04 does not add a second product surface under a stale scaffold name.
- User-facing menu copy should refer to Codogotchi, not Menubar.
- The menu bar micro-pet remains part of the app. This is not a separate floating-pet binary.

### Floating Surface

- Add a float-on-top desktop pet surface that can appear independently of the menu bar menu.
- The surface is visually transparent around the pet art and should not look like a normal document window.
- The default launch position is bottom-right on the active display, matching the Codex-style reference posture.
- The menu bar remains the always-available control anchor for show/hide and quit behavior.

### Drag And Resize

- Click-hold on the floating frame moves the pet around the screen.
- Click-hold on the resize affordance resizes the pet rather than moving it.
- The resize affordance is visible enough to discover but small enough not to dominate the pet.
- Hovering over the resize affordance should switch the cursor to a resize cursor when practical on macOS.
- The size range is bounded by the supplied Codex screenshots: a compact minimum that stays out of the way and a large maximum suitable for inspection and delight. Unbounded scaling is out of scope.

### Persistence

- The floating pet persists both position and size across app restarts.
- If the saved frame is off-screen, too close to an unavailable display, or invalid after display changes, the app falls back to a sane visible frame rather than restoring blindly.
- Persistence is local to the macOS app and does not change the `state.json` animation contract.

### Animation And State

- The floating pet consumes the same active pet configuration as the menu bar surface.
- The floating surface reflects the same live activity state as the menu bar surface during normal operation.
- Existing demo-mode and transition-log behavior remain available enough to validate floating-surface states without depending on live agent activity.
- Reserved Codex rows are consumed only by the floating surface:
  - `running-right` for rightward drag/movement feedback.
  - `running-left` for leftward drag/movement feedback.
  - `jumping` for hover, resize, or attention feedback where it fits the asset.
- Missing or unsupported interaction rows degrade gracefully to the ordinary current activity animation.

## Explicit Deferrals

- **Focus-aware visibility.** Desirable, but not the point of Phase 04. The pet is visible when enabled, regardless of frontmost app. App/process detection for Codex, Claude Code, Claude Desktop, and terminal foreground processes gets its own later product pass.
- **HP overlays, death/ghost, mood tints, and social-drama visuals.** These remain a later drama phase. Phase 04 is about the desktop surface and direct manipulation, not health rendering.
- **Pet picker and catalog.** Phase 04 uses the existing `~/.codogotchi/config.json` pet selection. It does not add catalog enumeration, validation across many pets, display names, or picker UI.
- **Richer pet manifest format.** The hardcoded row-map precedent remains acceptable for this phase. Multi-pet metadata and row-map standardization belong with catalog work.
- **Autonomous movement and physics.** The pet does not wander on its own, avoid windows, snap to edges, collapse into strips, or run pathfinding. The owner moves and sizes it directly.
- **Advanced display management.** Safe fallback is required; per-display preferences, Spaces-specific placement, edge docking, and multi-monitor policy controls are deferred.
- **Distribution polish.** Signed installer, notarization, Sparkle, launch-at-login, and public release packaging stay out. The owner still runs a private dev build.
- **Public marketing surface.** No README GIF campaign, Twitter-ready launch post, web armory tie-in, or public landing page.

## Exit Condition

Phase 04 is done when the owner can launch the macOS app as Codogotchi, see both the menu bar micro-pet and a transparent floating pet, drag the floating pet to a new location, resize it between the documented minimum and maximum, quit and relaunch with position and size restored, and watch the floating pet update from live or demo `state.json` activity without diverging from the menu bar state. The reserved mouse-interaction rows must be visibly exercised at least once, or gracefully skipped with documented evidence when the active asset lacks the row.

The phase is not done if the floating pet only works as a static enlarged image, loses placement every restart, opens off-screen after a display change, or forces the owner to choose between the menu bar surface and the floating surface.

## Retrospective

`required` - Phase 04 changes the native app boundary from a menu-bar renderer into a desktop companion, introduces the second AppKit/SpriteKit-style surface, locks drag/resize/persistence expectations, consumes the previously reserved mouse-interaction rows, and corrects the app identity from `Menubar` to `Codogotchi`. These are durable precedents for later HP, catalog, and distribution phases.
