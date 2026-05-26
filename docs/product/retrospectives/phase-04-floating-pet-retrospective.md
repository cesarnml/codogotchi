# Phase 04 — Floating pet retrospective

Source plan: [`docs/product/plans/phase-04.md`](../plans/phase-04.md).
Delivery plan: [`docs/product/delivery/phase-04/implementation-plan.md`](../delivery/phase-04/implementation-plan.md).

## Scope delivered

Tickets P4.01 → P4.09 (9/9) shipped as a stacked PR chain on `agents/p4-*`
branches, PRs [#45](https://github.com/cesarnml/codogotchi/pull/45) through
[#53](https://github.com/cesarnml/codogotchi/pull/53) (final PR number at
closeout). Delivered:

- macOS app identity rename (`Menubar` → `Codogotchi`, scheme/project/xcodegen);
- renderer-local persistence in `~/.codogotchi/app-state.json` with clamped
  min/max frame policy (96–512 pt);
- AppKit float-on-top panel shell with menu **Show/Hide Floating Pet** toggle;
- SpriteKit floating scene sharing composite resolution with the menu bar renderer;
- shared live/demo activity fanout so both surfaces stay aligned;
- drag, resize affordance, resize cursor, quit/relaunch persistence, and
  display-change reclamp;
- consumption of reserved Codex rows (`running-right`, `running-left`, `jumping`)
  for drag/resize feedback with graceful fallback;
- Phase 04 validation runbook at `docs/runbooks/phase-04-validation.md`;
- retrospective and doc sweep (this file).

## What went well

- **Rename-first sequencing paid off.** Landing P4.01 before any SpriteKit work
  kept scheme/product/menu churn out of floating-surface diffs. Later tickets
  could refer to `Codogotchi` consistently in tests, menu copy, and build
  scripts without mixing identity migration with behavior.
- **AppKit shell + SpriteKit renderer split matched the product boundary.**
  Transparency, float level, dragging, resizing, and `LSUIElement` ownership
  stayed in AppKit; layered sprite animation stayed in SpriteKit. Each layer
  had focused XCTest coverage (`FloatingPetControllerTests`,
  `FloatingPetSceneTests`) without the menu bar renderer needing to know panel
  geometry.
- **Separate `app-state.json` kept concerns honest.** Floating visibility,
  position, and size never leaked into `config.json` or `state.json`. Clamping
  at load time plus display-change notification gave safe fallback without
  building a multi-display preference system Phase 04 explicitly deferred.
- **Shared fanout before interaction polish.** P4.05 wired both renderers to the
  same activity stream before drag/resize (P4.06) and mouse-reactive rows
  (P4.07). That order made “menu bar vs floating disagree” a fanout bug, not an
  interaction bug — easier to diagnose.
- **Lightweight validation runbook at the end.** Owner attestation without a
  mandatory screenshot packet matched the private dev-build reality. The
  checklist still covers every product-plan exit condition that needs eyes on
  glass.

## Pain points

- **Visual QA remains owner-bound (expected cost).** SpriteKit frame timing,
  transparency around art, and resize affordance discoverability do not reduce
  to unit tests. The runbook helps, but Phase 04 still depends on a human
  running `bun run mac:build` and stepping through the checklist — unavoidable
  for this surface class.
- **Stacked Swift worktrees multiply DerivedData paths (avoidable friction).**
  Each ticket worktree builds its own `Codogotchi.app` under DerivedData.
  Validation notes should record which build was exercised; the runbook now
  documents the `find … Codogotchi.app` helper for that reason.
- **Historical docs lagged the rename until P4.09.** README and menubar README
  still described a menu-bar-only Phase 03 world mid-stack. Scoped doc sweep at
  the end worked, but future phases should update README status in the same
  ticket that changes user-visible app identity or primary workflow.

## Surprises

- **Pure-function interaction policy simplified mouse-row wiring.** Extracting
  `FloatingInteractionPolicy.resizedFrame` and reserved-row selection from drag
  delta made P4.07 testable without spinning up a full panel — the spec did not
  call out that shape explicitly, but it fell out naturally once hit-testing
  split drag body from resize affordance.
- **Display-change reclamp was more load-bearing than “nice to have.”** Saved
  frames from a laptop + external monitor setup go stale quickly. Startup clamp
  alone would have left off-screen pets after hot-unplug; listening for display
  parameter changes closed a real gap the product plan only hinted at.
- **Demo mode remained the fastest state-sync check.** Even with live hook
  wiring, `CODOGOTCHI_DEMO=1` is still the quickest way to prove both surfaces
  agree without inducing Claude/Codex events.

## What we'd do differently

- **Earlier README status bump.** We would update root README “Status” when
  P4.01 lands, not wait for P4.09. The original choice kept doc churn out of
  code tickets, but it left mid-phase readers thinking floating pet was still
  deferred.
- **Single “build path” note in ticket handoffs.** P4.08/P4.09 handoffs could
  have pointed at `Codogotchi.xcodeproj` + `bun run mac:build` explicitly
  once P4.01 merged — several docs still said `Menubar.xcodeproj` until this
  sweep.

## Net assessment

Phase 04 achieved its stated goal: Codogotchi is now a menu bar agent **plus**
a draggable, resizable, persistent floating desktop companion that tracks the
same activity state stream and exercises the reserved Codex interaction rows
where assets allow. Focus-aware visibility, HP/XP/stage visuals, catalog UI,
and distribution polish remain correctly deferred. The architecture choices
(AppKit shell, SpriteKit scene, separate app-state file, shared fanout) are
durable enough to build drama-phase visuals on later without revisiting the
surface split.

## Follow-up

- Run `docs/runbooks/phase-04-validation.md` on the owner's machine before
  closeout-stack and record pass/fail in the closeout PR or a short log entry.
- Phase 05+ planning: treat focus-aware visibility and HP overlays as separate
  product passes — do not extend the floating panel shell for those concerns.
- If multi-pet catalog work adds many new Swift files, invest in xcodegen-only
  workflow docs so PBX drift does not return.

_Created: 2026-05-26. PR #53 open at delivery time._
