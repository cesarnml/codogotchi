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
- **Seen:** 3× — `codogotchi-15` (P12): `StateJsonWriter.dismissAttention` was
  handed `state.d/` but treated it as a single file, so the call silently
  no-oped. `codogotchi-18` (P13): the p13.04 pool refactor swapped the single
  panel controller for a per-origin factory and **dropped the
  `onAttentionDismissed` wiring entirely**. `codogotchi-20` (P13): the same
  refactor never wired `reloadActivePet` to push the new pet into pool windows,
  so a Settings pet change didn't live-swap visible pets. The 3rd instance is a
  **different surface** (live pet swap, not attention), confirming the class is
  not over-fit to `dismissAttention`: the common root is *a behavior the old
  single owner performed was not re-established in the new owner*.
- **Proposed clause:** *"When a refactor replaces a single owner with a
  factory/pool/registry, enumerate every behavior the old owner performed —
  `.on<Event> =` callback assignments, side-effecting calls, and live-update
  paths (reload/replace/refresh) — and confirm each is re-established (or
  deliberately dropped) in the new path. Two tells: (a) a helper that fails
  silently needs an integration test asserting its side effect occurred; (b) a
  comment ADDED by the refactor that announces a new limitation ('retained until
  respawned', 'takes effect on next restart', 'X no longer happens until Y') is a
  regression smell — challenge it, do not accept it as intended."*
- **Caveat that blocks naive promotion:** the **detection lever varies by
  instance**, which complicates a single prompt clause. `codogotchi-18` was
  `qa-gap` (dropped wiring buried in an AppKit factory closure, not
  unit-reachable). `codogotchi-20` was `review-reachable` (the refactor left a
  self-documenting comment in the diff). So the class is real and now generalized
  (3×, two surfaces), but it splits across an integration/dogfood lever AND a
  diff-review lever — promotion may need *two* coordinated clauses (a review
  prompt for the self-documenting-comment tell, a phase-integration checklist for
  the silent ones) rather than one.
- **Status:** AT THRESHOLD (3×, generalized). Ready to promote, but decide the
  split first: a review-prompt clause for the comment-tell variant vs. a
  phase-integration-pass item for the silent variant. Promotion edits
  `adversarial-review-template.md` and is out of scope for the QC lane — route
  the promotion decision through planning/the review-template owner.

### `time-based-feature-tested-against-proxy-condition`
- **Seen:** 1× — `codogotchi-19` (P13). The "Dismiss after idle: N min" TTL was
  measured against slice *presence* (refreshed every poll) instead of *idle
  duration*, so it never fired for a still-running tool. Every unit test expired
  the window by feeding an **empty snapshot** — i.e. it tested slice *absence*
  (teardown), never the present-but-idle path the spec actually promised. The
  green test gave false confidence in a completely non-functional feature.
- **Proposed clause:** *"For any time-based feature (TTL, debounce, staleness,
  auto-dismiss, retry-after), name the exact signal that advances the clock —
  presence vs. activity vs. wall-time — and confirm the test holds the entity
  present-but-inactive across the threshold. A test that expires the entity by
  removing it is testing teardown, not the timeout. When an acceptance criterion
  is phrased as a real-world condition ('leave it idle', 'after no input'),
  reproduce that condition, not a convenient proxy that shares a code path by
  accident."*
- **Caveat that blocks naive promotion:** this is `qa-gap`-flavored
  (scenario-fidelity), not a diff-reading miss — the buggy code reads as a
  plausible last-seen TTL, so the lever is a test/dogfood-design rule more than
  an adversarial-review clause. Whether it belongs in the review prompt or a
  test-strategy checklist is unresolved at 1×.
- **Status:** WAITING — single instance. Promote (and decide review-clause vs.
  test-strategy-checklist) only on a second time-based feature with the same
  proxy-condition test gap.

### `user-hide-overwritten-by-periodic-respawn`
- **Seen:** 1× — `codogotchi-21` (P13). Hiding a floating pet removed the window
  but left no record of user intent. The pool's next `update()` tick found
  `windows[origin] == nil` and the origin still present in the snapshot, so it
  re-spawned the window immediately (~1 second later). Also: the menu's "Show Pet"
  item was always `action = nil`, so there was no interactive path to un-hide.
- **Proposed clause:** *"When a user-facing action removes an item from a pool or
  registry that is fed by a continuously-present backing source (a live snapshot,
  a poll result, a stream), removing the item from the in-memory collection is not
  enough — the pool's next refresh will re-add it from the source. A persistent
  user-intent flag (an explicit hide/pin/exclude set) is the correct guard.
  Attack surface: for any periodic `update()` or refresh that spawns windows/rows
  from a live source, ask 'if setVisible(false) or remove() fires but the source
  is still present, what does the next refresh do?'"*
- **Status:** WAITING — single instance. Needs ≥1 more occurrence to confirm
  the class before promoting. Note also: after hiding, the pet re-spawned at the
  default bottom-left spawn position rather than its last persisted position —
  a related but distinct open issue deferred from this QC fix.

## Open meta-question (for the eventual `/soa quality-control` skill)

The 7 existing diff-derived classes are backend/CLI-shaped. codogotchi's
post-phase fixes are overwhelmingly UI/interaction/animation. Likely upstream
finding once evidence accumulates: UI-heavy SoA repos need a **parallel
UI-review class family** — gesture state-machine integrity, animation-frame
continuity, screen-space vs view-space coordinate bugs, compound-widget cohesion,
affordance hit-testing. Hold until the ledger has enough rows to name the cut.
