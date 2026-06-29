# Promotion Queue

Candidate clauses for the upstream adversarial-review prompt
(`.son-of-anton/docs/template/delivery/adversarial-review-template.md`,
"diff-derived classes"). A class is promoted **only after it recurs ≥2–3×**
across phases or repos — every class added taxes every future review, so the
prompt absorbs only *proven-recurrent, review-reachable* gaps. Capture
(`ledger.jsonl`) is the staging area; promotion is a separate, rarer action.

## Candidates (not yet promoted)

### `compound-widget-cohesion-under-transform`
- **Seen:** 1× — `codogotchi-01` (attention bubble detaches from pet on drag).
- **Proposed clause:** *"For any draggable/resizable container, enumerate every
  child or attached overlay (bubbles, badges, affordances, pills) and assert each
  tracks the same transform. A multi-part visual whole must move atomically — the
  UI analogue of cross-file-atomicity."*
- **Caveat that blocks naive promotion:** only review-reachable when container
  and overlay live in the **same ticket diff**. In `codogotchi-01` they shipped
  in different phases (P4 pet, P6 bubble), so no per-ticket review saw both. The
  real lever may be a **phase-level integration review pass**, not a per-ticket
  prompt clause. Resolve this before promoting.
- **Status:** WAITING — needs ≥1 more occurrence to confirm the class and decide
  per-ticket-clause vs phase-integration-pass.

### `control-signal-starved-by-change-gated-callback`
- **Seen:** 2× — `codogotchi-01` round-1 (bubble re-anchor hung on the
  persist-on-`mouseUp` handler, so it only fired at drag *end*) and
  `codogotchi-10` (HUD `rpg_hud_enabled` re-read only inside a poll callback
  gated on RPG-value deltas, so a static-stats toggle never applied until
  restart). Note `codogotchi-01`'s `defect_class` string named the *symptom*
  (widget cohesion); this piggyback-starvation pattern lived in its
  `prompt_lesson`. Both are the same root cause.
- **Proposed clause:** *"For any setting, flag, or control signal that must
  affect a running view, identify the single runtime path that re-reads it and
  ask under what condition that path executes. If that trigger is unrelated to
  the signal's own change (a delta gate, a `mouseUp`, a conditional periodic
  emit), the signal is starved whenever that condition is absent. A control
  signal must ride a path triggered by its own change. Corollary: persisting to
  config is not applying — a settings write needs an explicit live-apply call
  into the running view, distinct from whatever reads config at startup."*
- **Caveat that blocks naive promotion:** review-reachability depends on the
  re-read path and the toggle being visible together. In `codogotchi-10` both
  were in the P10.08 diff (clear review-reachable); in `codogotchi-01` round-1
  the starving handler's `mouseUp`-only firing was a phase-04 perf decision not
  in the phase-06 bubble diff — so the *demonstrability* varies by how far the
  triggering condition sits from the change under review.
- **Status:** WAITING at the 2× bar — strongest UI-family candidate so far.
  One more occurrence (ideally cross-repo) should settle whether it promotes as
  a per-ticket prompt clause or needs the phase-integration-pass treatment that
  `compound-widget-cohesion-under-transform` also points at.

### `side-effect-call-dropped-or-mis-targeted-in-refactor`
- **Seen:** 2× — both on `StateJsonWriter.dismissAttention`, both surfacing as
  the attention bubble failing to clear. `codogotchi-15` (P12): the writer was
  handed `state.d/` but treated it as a single file, so the call silently
  no-oped. `codogotchi-18` (P13): the p13.04 pool refactor swapped the single
  panel controller for a per-origin factory and **dropped the
  `onAttentionDismissed` wiring entirely**, so the call site vanished. Same
  feature broke twice across two consecutive phase migrations, both times
  invisible to units.
- **Proposed clause:** *"When a refactor replaces a single owner with a
  factory/pool/registry, grep the removed owner for every `.on<Event> =` /
  callback assignment and every side-effecting call it made, and confirm each is
  re-established (or deliberately dropped) in the new path. Pair this with: a
  helper that fails silently (returns void, swallows errors) must have an
  integration test asserting its side effect actually occurred — unit-passing
  the helper and unit-passing the caller in isolation does not prove they are
  wired together."*
- **Caveat that blocks naive promotion:** the dropped wiring lives in an AppKit
  factory closure (live `NSStatusBar`/`NSPanel` + poll loop), so it is **not
  unit-reachable** — this is a `qa-gap`/integration-pass lever, not a per-ticket
  diff-review clause. The recurrence is also narrow (same function twice), so the
  class may be over-fit to `dismissAttention`; a third, unrelated instance would
  confirm it generalizes.
- **Status:** WAITING at the 2× bar — same-function recurrence is suggestive but
  not yet proof of a general class. Reassess on the next dropped/mis-targeted
  side-effect from a refactor.

## Open meta-question (for the eventual `/soa quality-control` skill)

The 7 existing diff-derived classes are backend/CLI-shaped. codogotchi's
post-phase fixes are overwhelmingly UI/interaction/animation. Likely upstream
finding once evidence accumulates: UI-heavy SoA repos need a **parallel
UI-review class family** — gesture state-machine integrity, animation-frame
continuity, screen-space vs view-space coordinate bugs, compound-widget cohesion,
affordance hit-testing. Hold until the ledger has enough rows to name the cut.
