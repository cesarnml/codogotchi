# Phase 17: Surface Convergence ("One Renderer, Two Skins")

**Delivery status:** Product plan approved 2026-07-12 — awaiting `/soa decompose`.

## TL;DR

**Goal:** Make three-surface parity (Own pet / Minimalist strip / Combined window) structural instead of a code-review discipline — one prompt component, one renderer protocol, one chrome coordinator — so a fix or affordance lands once instead of N times with silent-forgetting as the failure mode.

**Ships:**

- One shared prompt/dismissal component: a single dismissal observer stack and a single `[PromptItem]` builder parameterized by window-shape capabilities; the two drifting `presentHidePrompt` implementations collapse to one.
- One renderer protocol with two implementations, replacing `FloatingPetPanelManaging` / `MinimalistPanelManaging`; `MenubarApp`'s two ~100-line factory closures collapse toward one parameterized factory.
- A Seam-2 router type owning "which slices does this window's action touch" targeting, leaving factories as dumb `panel.onX = { router.handle(.x, for: key) }` wiring.
- A chrome-flock coordinator: one component owning "these chrome panels (badge/bubble/HUD) fly in formation with this host window" — anchoring math, drag routing, fronting rules — consumed by all three shapes.
- A developer-approved capability matrix (window shape × affordance), drafted **first** as the convergence spec and enforced at exit as "code matches matrix."
- Local-only dogfood DMG at closeout (no public GitHub release; Track 2 ships v3).

**Defers:** `update()` pipeline changes (Phase 18); new affordances of any kind (v4); re-anchor cadence, screen-edge behavior, and other Chapter-14 chrome tuning; any intentional behavior change.

---

Phase 16 closed 2026-07-12 (retrospective written, dogfood DMG as daily driver), landing the layer directories, god-file splits, and the `WindowKey` type this phase builds on. Today each of the three window shapes hand-rolls the same machinery — prompt construction, dismissal observers, chrome anchoring, drag routing — and the cost is proven, not speculative: the "clicks elsewhere in-app don't dismiss the prompt" bug had to be fixed **three times** (Panel Size pill, `FloatingPetInteractionView`, `MinimalistBadgeView`) because each surface owns its own observer stack. This is the second of the three-phase Track 4 consolidation program (16 → 17 → 18), run serially under the program invariants recorded in the Phase 16 plan.

## Phase Goal

This phase should leave the product in a state where:

- A prompt or dismissal fix is written once and every window shape gets it — there is exactly one dismissal observer stack and one prompt-item builder in the codebase, with per-shape differences expressed as capability parameters, not separate implementations.
- A developer adding a window-shape behavior implements one renderer protocol; `MenubarApp` wiring contains no parallel comment blocks that must be "kept honest by hand."
- Chrome panels (badge/bubble/HUD) are anchored, drag-routed, and fronted by one coordinator across all three shapes, reproducing each shape's current behavior verbatim.
- Cross-surface affordance parity is auditable by diffing code against a developer-approved capability matrix, with intentional differences (e.g. Panel Size only on Minimalist, Combined-key rename semantics) recorded as capabilities rather than rediscovered as suspected drift.
- The app behaves identically to the Phase 16 dogfood build — full existing suite green, and the dogfood build survives daily-driver use across all three window shapes with no unexplained regressions.

## Committed Scope

### Program invariants (binding on this phase)

- **Behavior bar: freeze + bug fixes.** Zero intentional user-visible change. Full existing suite green per ticket. Genuine pre-existing bugs exposed by the work are fixed in separate commits with review-gap ledger entries.
- **No big-bang.** Every ticket independently landable and behavior-neutral.
- **Serial program.** Phase 18 does not begin execution until this phase's exit condition is met.

### Capability matrix (drafted first — the convergence spec)

- Enumerate the current shape × affordance grid from the code **before any convergence work**, with each cross-shape difference marked `proposed: bug | intentional`.
- **Every drift row gets explicit developer disposition before any restoration commit lands.** Default under uncertainty is "intentional, documented" — never "fix." Known traps recorded up front: Combined/plain-origin rename semantics are confirmed design; Own/Minimalist is a known parity seam.
- Drift dispositioned as a bug is restored in a separate commit with a review-gap ledger entry (per the program behavior bar); dispositioned-intentional differences become named capabilities.
- Amendments discovered mid-phase (missed affordances) route back through developer sign-off before the matrix changes.
- The approved matrix is a committed doc artifact and the exit gate's reference.

### Shared prompt/dismissal component

- One dismissal observer stack (global monitors + local monitors + resign-active) owned by (or adjacent to) `FloatingPetPromptCoordinator`, consumed by every prompt-presenting surface.
- One `[PromptItem]` builder parameterized by window-shape capabilities; the two `presentHidePrompt` implementations (Own's Prune offer, Minimalist's Hide retitle, the mode-switch pill) resolve into it.
- Views reduce to "present at this anchor with these capabilities."

### Renderer protocol convergence + router (one workstream, both committed)

- `FloatingPetPanelManaging` / `MinimalistPanelManaging` converge to one renderer protocol with two implementations — "one renderer interface, two skins."
- The Seam-2 router type is **committed scope, not stretch**: targeting logic ("which slices does this window's action touch") gets one home, and the `MenubarApp` factory closures collapse to one parameterized factory of dumb `panel.onX = { router.handle(.x, for: key) }` wiring. `MenubarApp` is disrupted once, in this phase, not twice across two dogfood windows.

### Chrome-flock coordinator (committed, mechanics-only)

- One component owning chrome-panel formation flying for a host window: anchoring math, drag routing from chrome into the host, z-order/fronting rules — replacing the three per-shape hand-sewn implementations.
- **Bounded to mechanics:** per-shape behavior is preserved verbatim. Where the three shapes' current behaviors genuinely differ, the coordinator reproduces the differences as capabilities rather than converging them.
- Re-anchor cadence, screen-edge behavior, and any Chapter-14 tuning are explicitly out (see Deferrals).

### Closeout release (mirrors Phase 16: local-only)

- Package a dogfood DMG via the normal packaging script and install it as the daily driver.
- **No public GitHub release and no download-page update** — behavior-neutral phases don't publish; the next public release ships with Track 2 / v3.

## Explicit Deferrals

- **`update()` pipeline restructuring (derive/diff/apply)** — Phase 18's workstream; this phase touches the view layer and factory wiring, not pool policy.
- **New affordances of any kind** — the matrix documents what exists; adding rows is v4 work.
- **Re-anchor cadence, screen-edge behavior, and Chapter-14 chrome tuning** — the coordinator unifies mechanics only; changing when/how chrome re-anchors is behavior change and out of the program bar.
- **Intentional behavior changes** — including "while we're in here" improvements; anything user-visible found broken is a separate-commit bug fix with a ledger entry, gated by developer disposition per the matrix rules above.
- **Public release / notarization / Sparkle** — Track 2; this phase's artifact is a local dogfood DMG only.

## Exit Condition

The phase is done when all of the following are demonstrably true on `v3_preview`:

1. **One prompt system:** exactly one dismissal observer stack and one prompt-item builder exist in the codebase; no surface owns a private `presentHidePrompt`.
2. **One renderer protocol:** `FloatingPetPanelManaging` and `MinimalistPanelManaging` no longer exist as separate protocols; the router type owns targeting; `MenubarApp` factory wiring is deduplicated with no parallel comment blocks.
3. **One chrome coordinator:** badge/bubble/HUD anchoring, drag routing, and fronting are implemented once and consumed by all three shapes, with per-shape behavior verbatim.
4. **Matrix matches code:** the developer-approved capability matrix is committed and a code audit against it shows every affordance present per the matrix, every intentional difference named as a capability, and every restored-drift fix carrying a ledger entry.
5. **Behavior bar:** full existing suite green; `bun run verify` and `bun run ci:quiet` pass.
6. **Dogfood:** a local DMG is packaged, installed, and running as the daily driver.

**Phase 18 execution gate:** Phase 18 execution starts only after (a) the dogfood build has served as daily driver with no unexplained regressions **and the soak has explicitly exercised all three window shapes — Own, Minimalist, and Combined** (daily-driver use alone can go days without touching Minimalist; the three-shape checklist is part of the gate, with no fixed calendar soak) — and (b) the Phase 17 retrospective is written. Phase 18 *planning* may proceed in parallel during the soak.

## Retrospective

`required` — architecture/process impact: Phase 18 restructures `update()` on top of this phase's renderer protocol and chrome coordinator; the retro is the checkpoint that validates the view-layer foundation before the pool pipeline inherits it, and it is mechanically required by the Phase 18 execution gate.
