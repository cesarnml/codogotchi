# Phase 18 Draft — Pool Pipeline Split (Derive / Diff / Apply)

_Drafted: 2026-07-11_
_Status: Draft input for `/soa plan` — third of the three-phase Track 4 architectural consolidation program (16 → 17 → 18); requires Phases 16 and 17 closed_
_Source: `/soa ideate` session over `notes/private/codogotchi-v3-polish-roadmap.md` (Track 4), `docs/product/delivery/phase-15/post-phase-15-mainline-sweep.md`, Dev Guide ch. 09 ("the pool") and ch. 10 (Seam 4)_

---

## Program context

See `phase-16-mechanical-consolidation.md` for the shared program invariants
(freeze + bug fixes behavior bar, dogfood release per phase, serial
16 → 17 → 18 → Track 2, no big-bang). This phase consumes Phase 16's
`WindowKey` and `SessionLifecycle` types and Phase 17's converged renderer
protocol; it is deliberately last so pool-pipeline regressions never share a
dogfood window with view-layer regressions.

---

## Thesis

Separate "which pets should exist" from "make it so."
`FloatingPetWindowPool.update()` is today a ~10-step imperative pipeline
(in a 1,310-line pool) where TTL, last-active immunity, mode transitions,
combined folding, session caps, eviction, grandfather gating, hidden keys,
and spawning interleave — policy and side effects in one long recipe. The
target shape (Seam 4):

```
derive : (Snapshot, Customization, Clocks, HiddenKeys) → DesiredWindows   // pure
diff   : (CurrentWindows, DesiredWindows) → [SpawnKey], [DismissKey], [UpdateKey]
apply  : effects only — factories, teardown, per-tick pushes
```

This is the last chance to do it before v4 piles on: the v4 Stats tab and
the hook-stamped prompt-timestamp architecture (see the roadmap's v4 note)
both land directly on this pipeline. It is also the refactor with the
strongest evidence base — nearly every Phase 15 QC fix (the mainline sweep's
teardown, eviction, grandfather, and hide/cap-incumbency buckets) was a
2–5-line condition gate inside `update()` that had been missed because the
pipeline's step-ordering invariants are implicit.

## The problem

- Policy decisions are only testable through their side effects: you can't
  check "who should be on screen" without stub window controllers actually
  spawning windows.
- Every change requires re-reading the whole pipeline to find the step (and
  step-ordering invariant) about to be violated. The extensive comments
  exist *because* they have to.
- The Phase 15 QC record is the receipts: four separate mode-transition
  teardown gaps, eviction frame-inheritance, grandfather gate bugs, and
  three hide-vs-cap-incumbency fixes — all missed branches of this one
  method.
- State that should be derivation input (hidden keys, clocks, grandfather
  activation stamps) lives as pool mutable state interleaved with effects.

## Proposed scope

1. **Pure `derive()`** producing a `DesiredWindows` value — consuming the
   reader snapshot, customization, the three clocks (via Phase 16's
   `SessionLifecycle` classifier), hidden keys, cap/eviction policy,
   last-active election, grandfather gate, and combined folding. Keyed by
   Phase 16's `WindowKey`.
2. **Mechanical `diff`** — desired vs. current window set →
   spawn/dismiss/update sets, plus the frame-inheritance directives
   (eviction promotion and grandfather collapse inherit frames — encoded as
   data in the diff, not as apply-time policy).
3. **Effect-only `apply`** — factories (Phase 17's converged shape),
   teardown, per-tick pushes (state, attention, gate badges, RPG state,
   labels, scale). Zero policy decisions: any policy found hiding here moves
   into `derive` (the seams doc's "exercise 3" test).
4. **Property-style tests on `derive`** — feed clocks, caps, and hidden-key
   sets; assert the desired set. The Phase 15 QC gap classes (teardown on
   mode transition, hide/cap interaction, grandfather admission) become
   cheap table-driven cases. Existing 900+ tests survive against the
   composed whole.

## Explicitly out of scope

- The v4 hook-stamped `prompt_started_at` architecture (schema bump + hook
  binary + five installers) — explicitly a v4 item per the roadmap. This
  phase only ensures the pipeline it lands on is derivable/testable.
- Any change to reader/writer disk contracts, clock defaults, or eviction
  policy semantics — behavior freeze applies; `derive` must reproduce
  today's decisions exactly.
- Performance work beyond incidental (the pipeline runs once per poll tick;
  no budget change expected).

## Success criteria (draft — to be firmed in `/soa plan`)

- `update()` (or its successor) is a composition of `derive` / `diff` /
  `apply`; `derive` is a pure function with no AppKit imports.
- `DesiredWindows` requires zero additional policy decisions in `apply` —
  reviewed against every current `update()` step.
- Property/table tests cover the Phase 15 QC gap classes; full existing
  suite green.
- Dogfood release cut at closeout; this closes Track 4 and unblocks
  Track 2 (notarize + Sparkle) as the final v3 work item.

## Open questions for `/soa plan`

- The exact `DesiredWindows` field spec — what fields (window key, shape,
  session number, label, visibility, frame directive, chrome payloads?) so
  `apply` needs zero policy. The seams doc's exercise 3 sketch is the
  starting point; anything missed is a policy currently hiding inside an
  effect.
- Where grandfather-gate activation state and the session-number free-list
  allocator live — derive input (persisted pool state passed in) vs.
  internal derive state threaded between ticks.
- Is the last-active TTL-immunity election part of `derive` or a clock-like
  input computed upstream?
- Migration strategy: strangler (steps peel off into `derive` one at a time
  behind the existing pipeline) vs. parallel implementation with a
  shadow-compare tick (run both, assert same decisions, then cut over)?
- Do per-tick pushes (attention, gate badges, RPG state) belong in the
  desired-state value or remain a separate apply channel?

> Next step (after Phase 17 closes): `/soa plan docs/product/drafts/phase-18-pool-derive-diff-apply.md`
