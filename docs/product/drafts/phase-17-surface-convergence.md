# Phase 17 Draft — Surface Convergence ("One Renderer, Two Skins")

_Drafted: 2026-07-11_
_Status: Draft input for `/soa plan` — second of the three-phase Track 4 architectural consolidation program (16 → 17 → 18); requires Phase 16 closed_
_Source: `/soa ideate` session over `notes/private/codogotchi-v3-polish-roadmap.md` (Track 4), `docs/product/delivery/phase-15/post-phase-15-mainline-sweep.md`, Dev Guide ch. 09/10 (Seam 3, "three window shapes, one protocol")_

---

## Program context

See `phase-16-mechanical-consolidation.md` for the shared program invariants
(freeze + bug fixes behavior bar, dogfood release per phase, serial
16 → 17 → 18 → Track 2, no big-bang). This phase depends on Phase 16's
`WindowKey` type and split view files being landed.

---

## Thesis

Make three-surface parity (Own pet / Minimalist strip / Combined window)
**structural instead of a code-review discipline**. Today each surface
hand-rolls the same machinery — right-click prompt construction, dismissal
observer stacks, chrome anchoring, drag routing — and every fix or new
affordance must be applied N times, with forgetting one copy being silent.
After this phase, parity is a type: one prompt component, one renderer
protocol, one chrome coordinator.

## The problem

- **The proven bug class:** the "clicks elsewhere in-app don't dismiss the
  prompt" bug (`b2820f98` window) had to be fixed **three times** — once for
  the Panel Size pill, once each in `FloatingPetInteractionView` and
  `MinimalistBadgeView` — because each surface owns its own observer stack
  (global monitors + local monitors + resign-active).
- **Two drifting `presentHidePrompt` implementations** build the prompt-item
  lists independently (Own offers Prune; Minimalist retitles Hide; both must
  remember the mode-switch pill by hand). The roadmap's cross-window
  affordance-parity audit "keeps being done by hand."
- **Two panel-managing protocols** (`FloatingPetPanelManaging` /
  `MinimalistPanelManaging`) force `MenubarApp`'s two ~100-line factory
  closures to duplicate targeting and wiring logic in parallel comment
  blocks (Seam 2's god-closures are half a parity problem).
- **Chrome is hand-sewn per shape:** every badge/bubble/HUD is its own
  floating `NSPanel` re-anchored to the host on drags and poll ticks, and
  each of the three shapes sews its own flock together (anchoring math, drag
  routing from chrome into the host, z-order/fronting rules).

## Proposed scope

1. **Shared prompt/dismissal component** — owned by (or next to)
   `FloatingPetPromptCoordinator`: a single observer stack and a single
   `[PromptItem]` builder parameterized by window-shape **capabilities**,
   with the views reduced to "present at this anchor with these
   capabilities." Resolves the two `presentHidePrompt` implementations into
   one.
2. **Renderer protocol convergence** — `FloatingPetPanelManaging` /
   `MinimalistPanelManaging` converge to one renderer protocol with two
   implementations ("one renderer interface, two skins"). The `MenubarApp`
   factory closures collapse toward one parameterized factory; the
   "which slices does this window's action touch" targeting logic gets one
   home (router type per Seam 2), leaving factories as dumb
   `panel.onX = { router.handle(.x, for: key) }` wiring.
3. **Chrome-flock coordinator** — unify badge/bubble/HUD anchoring and drag
   routing across all three shapes: one component owning "these chrome
   panels fly in formation with this host window," replacing per-shape
   anchoring/drag/fronting code.
4. **Affordance-parity audit as exit gate** — an explicit capability matrix
   (window shape × affordance) documented once; every affordance present per
   the matrix, intentional differences (e.g. Panel Size only on Minimalist)
   recorded as capabilities rather than drift.

## Explicitly out of scope

- `update()` pipeline changes (Phase 18) — this phase touches the view
  layer and factory wiring, not pool policy.
- New affordances of any kind — the matrix documents what exists; adding
  rows is v4 work.
- Behavior changes (see program behavior bar); parity **drift** discovered
  during the audit is triaged case-by-case: restoring the evidently-intended
  behavior counts as a bug fix (separate commit + ledger entry), anything
  ambiguous is documented as an intentional capability and left alone.

## Success criteria (draft — to be firmed in `/soa plan`)

- One `presentHidePrompt` / prompt-builder implementation; one dismissal
  observer stack in the codebase.
- One renderer protocol; `MenubarApp` factory wiring deduplicated (no
  parallel comment blocks to "keep honest by hand").
- Chrome anchoring/drag routing implemented once, consumed by all three
  shapes.
- The capability matrix exists as a doc artifact and matches the code.
- Full existing suite green; dogfood release cut at closeout.

## Open questions for `/soa plan`

- Where does the capability matrix live in code — on `WindowKey`, or a
  separate window-shape descriptor type the renderer exposes?
- Are any Combined-window affordance differences intentional and
  load-bearing (e.g. rename semantics on the combined key)? Enumerate before
  converging.
- Does the router type (Seam 2) belong here or partly in Phase 16?
  (Current draft: here, since it collapses with factory convergence.)
- How far does the chrome coordinator go into Chapter-14 territory
  (re-anchor cadence, screen-edge behavior) before it stops being
  behavior-neutral?

> Next step (after Phase 16 closes): `/soa plan docs/product/drafts/phase-17-surface-convergence.md`
