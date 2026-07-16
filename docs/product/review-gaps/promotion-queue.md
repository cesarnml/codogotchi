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
- **Seen:** 3× — `codogotchi-01` round-1 (bubble re-anchor hung on the
  persist-on-`mouseUp` handler, so it only fired at drag *end*) and
  `codogotchi-10` (HUD `rpg_hud_enabled` re-read only inside a poll callback
  gated on RPG-value deltas, so a static-stats toggle never applied until
  restart). Note `codogotchi-01`'s `defect_class` string named the *symptom*
  (widget cohesion); this piggyback-starvation pattern lived in its
  `prompt_lesson`. Both are the same root cause. 3rd instance
  (`2e817a9b`, phase-19 QC): right-click Rename/Sync Label wrote
  `session-labels.json` synchronously, but `SessionsTabViewModel` reads labels
  through `FloatingPetWindowPool.sessionDisplayLabel`'s `lastDesired` snapshot,
  which only rebuilds on the next ~1s poll tick — a re-read path gated on an
  unrelated periodic trigger, not the label's own change. Same fix commit also
  hit the inverse timing bug (a synchronous refresh racing an *async*
  `handleForceIdle` background-queue write) — same root cause, opposite
  direction: the dependent view's re-read must be triggered by the signal's
  own change, whichever side is slower.
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
- **Status:** AT THRESHOLD (3×). Ready to promote — decide per-ticket prompt
  clause vs. the phase-integration-pass treatment that
  `compound-widget-cohesion-under-transform` also points at before writing the
  clause into `adversarial-review-template.md`.

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
- **Seen:** 2× — `codogotchi-21` (P13) and `codogotchi-36` (phase-15,
  recurrence of `codogotchi-21`). `codogotchi-21`: hiding a floating pet
  removed the window but left no record of user intent, so the pool's next
  `update()` tick found the origin still present in the snapshot and
  re-spawned it (~1 second later) — fixed by adding the in-memory
  `userHiddenWindowKeys` set as the user-intent guard. `codogotchi-36`: that
  guard was real but scoped to process lifetime only — it was never wired to
  any on-disk persistence, so a full app quit/relaunch was itself a "periodic
  respawn" event from the guard's perspective, and a hidden pet whose
  session-pet TTL slice was still alive would silently reappear. Same
  underlying class, one layer up: the durable-guard fix from the first
  occurrence didn't generalize to every refresh boundary that can re-observe
  the backing source, only the in-tick one.
- **Proposed clause:** *"When a user-facing action removes an item from a pool
  or registry that is fed by a continuously-present backing source (a live
  snapshot, a poll result, a stream, or a re-read of on-disk state at process
  start), removing the item from the in-memory collection is not enough — ANY
  refresh boundary that re-observes the source will re-add it. A persistent
  user-intent flag (an explicit hide/pin/exclude set) is the correct guard,
  but the flag itself must survive every refresh boundary the source can
  cross, not just the most obvious one (a poll tick) — explicitly check
  process restart, too, if the source persists independently of the running
  process (e.g. a TTL'd on-disk slice)."*
- **Status:** CANDIDATE FOR PROMOTION — 2 occurrences, same class, escalating
  durability boundary (in-tick → cross-process). Recommend folding into the
  adversarial-review template as a dedicated check: "for any user-hide/pin/
  exclude guard, does it survive every way the backing source can resurface
  the same item, including an app/process restart?" The related spawn-position
  issue (pets always spawning at the same bottom-left coordinate) was fixed in
  `codogotchi-22` (per-origin position persistence, schema v3) — the same
  session established `AppStateStore` as the durable-guard mechanism that
  `codogotchi-36` extended to hidden-state.

### `pool-spawn-position-not-per-origin`
- **Seen:** 1× — `codogotchi-22` (P13). The pool factory passed `saveState: { _ in }` to
  suppress the single-owner global-visibility write, but this also silently discarded
  per-owner frame persistence. All pets spawned at the same coordinate because every
  controller called `AppStateStore.load()` (global frame) and never wrote back.
- **Proposed clause:** *"When a refactor replaces a single stateful owner with a pool or
  registry, enumerate every piece of per-owner state (position, saved frame, last-seen
  timestamp, visibility flag) and explicitly decide: global, per-owner, or discarded.
  A no-op override in a factory closure (`saveState: { _ in }`) suppresses all side-effects
  indiscriminately — confirm it is not also suppressing a necessary persistence path.
  Ask: does each pool member need its own copy of this state, or is the global copy
  correct for multi-instance use?"*
- **Relationship to `user-hide-overwritten-by-periodic-respawn`:** same root class
  (pool spawning with shared/missing state instead of per-owner state); different
  manifestation (position vs. visibility intent). Possible merge into a broader
  `pool-refactor-drops-per-owner-state` class if a third occurrence confirms the pattern.
- **Status:** WAITING — 1 occurrence. Needs ≥1 more to confirm before promoting.

### `new-enum-case-skips-existing-transition-matrix`
- **Seen:** 3× — `codogotchi-06` (P14). `FloatingPetWindowPool` already had
  explicit per-tick teardown for `own->off` and `own->combined` mode
  transitions (each added when an earlier ticket needed that specific pair).
  P14.06 added a third `PlatformMode` case, `.minimalist`, routed through the
  same per-origin window factory — but no one re-checked the full transition
  matrix against the now-3-case enum, so `own<->minimalist` had zero teardown.
  Switching a platform's mode in Settings silently no-op'd (the stale window
  kept running) unless TTL or restart happened to clear it.
  `codogotchi-28` (P15 QC, same file): P15.03's `resolveRenderKeys` moved
  combined-mode folding upstream (pre-folding to the literal `"combined"` key
  before the pool ever sees the snapshot), but Step 6a's `own/minimalist ->
  combined` teardown still scanned the snapshot's own keys to find what to
  collapse — a reactive, one-pair-at-a-time branch exactly like `codogotchi-06`'s.
  With pre-folded input the origin's key never reappeared, so the branch never
  ran. A second, distinct bug on the same transition matrix also surfaced:
  `combined -> own/minimalist` teardown gated dismissal on last-active TTL
  immunity even when zero origins were combined-mode anymore, which could
  nondeterministically stick on a same-tick timestamp tie.
  `codogotchi-29` (P15 QC, same file, same round): a THIRD trigger — toggling
  `sessionPetsEnabled` for an origin changes render-key SHAPE (plain `origin`
  vs `origin:session_id`) independent of `PlatformMode` entirely. Neither
  direction (enabling or disabling) was covered by any existing branch,
  including the two just-added by `codogotchi-28`: the mode-mismatch collapse
  only re-checks a key still present under the SAME string this tick, and the
  combined-collapse only fires for keys resolving to `"combined"`. A toggle
  that changes key shape without touching mode falls through every branch.
- **Proposed clause:** *"When a ticket adds a new case to an enum that drives a
  switch/factory dispatch inside a stateful pool or registry, OR refactors
  where/how an existing case's data is shaped upstream, enumerate the full
  N x N transition matrix against every reactive, one-pair-at-a-time teardown
  branch already in the pool — do not assume an existing branch still fires
  correctly just because its code is untouched. Each teardown branch
  (`if mode == X` cleanup, `if renderKey in someSnapshotSet` cleanup) was added
  reactively for one pair under one specific data shape; a new case OR a
  changed upstream data shape can silently make an existing branch's condition
  never match, without anyone touching that branch's code."*
- **Relationship to `side-effect-call-dropped-or-mis-targeted-in-refactor`:**
  still a close sibling ("old assumption not re-established for the new
  shape/case"), but now confirmed on THREE distinct triggers, all in the exact
  same pool file's reactive per-pair teardown branches: enum-case addition
  (`codogotchi-06`), an upstream data-shape refactor (`codogotchi-28`), and a
  settings toggle that reshapes render keys independent of mode
  (`codogotchi-29`). Each new fix in this same P15 QC round patched the
  specific case just found without re-deriving the matrix, and each time a
  DIFFERENT uncovered transition surfaced immediately after — this is no
  longer a coincidence, it is the structure of the file producing gaps on a
  predictable cadence.
- **Explicit developer decision (2026-07-03):** discussed promoting to a full
  derived-transition-matrix rewrite (Option B) vs. continuing ad-hoc per-case
  patches. Developer chose to continue ad-hoc patching for now to avoid
  delaying the v2 release, with the refactor deferred as a known, accepted
  cost — not an oversight. Route the refactor decision through `/soa plan`
  when there is room in the roadmap; do not re-litigate the ad-hoc-vs-refactor
  call inside a future QC round without new information.
- **Status:** AT THRESHOLD (3×, same file, three different triggers, explicit
  developer sign-off to keep patching ad hoc for now). Promote the review-prompt
  clause regardless of the refactor timeline — it costs nothing to add and
  would have flagged `codogotchi-29` before it shipped. The standalone
  refactor ticket remains available whenever the developer wants to schedule
  it; this is not a call to make unilaterally from the QC lane.

### `flagged-spec-divergence-dropped-without-escalation`
- **Seen:** 1× — P14.06 (minimalist window). The subagent review prompt itself
  named the gap: "The ticket asks for badge/attention composition; the
  implementation uses a new compact strip view, so decide whether this is an
  acceptable implementation detail or a product/spec drift." The review then
  recorded `"outcome": "clean"`, `"findings": []` — the question was posed and
  never answered. The ticket spec (`ticket-06-minimalist-window.md:32`)
  explicitly named the anti-pattern being committed ("do not fork their
  rendering"), and the shipped code did exactly that: `MinimalistStripView` is
  four bare `NSTextField`s, reusing none of `GateBadgeView`,
  `AnimationBadgeView`, or `AttentionBubblePanel`. This was not a silent miss —
  the reviewer's own uncertainty was captured in the review prompt and then
  discarded by the outcome-recording step.
- **Proposed clause / process fix:** *"When a review prompt poses an open
  decide-this question about spec/implementation divergence, the orchestrator
  must not allow the review outcome to resolve to 'clean' with empty findings
  while that question is unanswered. A self-flagged uncertainty is a forced
  escalation, not an optional one — route it to the human operator rather than
  letting a downstream 'findings: []' silently close it."*
- **Caveat that blocks naive promotion:** this is an orchestration/tooling gap
  (how review outcomes are reconciled against open questions in the review
  prompt), not a prompt-clause gap — promoting it may mean a change to the SoA
  review-recording pipeline itself (upstream `son-of-anton`), not the
  adversarial-review template. Needs scoping with the subtree owner before
  deciding where the fix lives.
- **Status:** WAITING — single instance, first of its kind in the ledger
  (distinct from the per-ticket review-content classes above; this is about
  the *outcome-recording* step swallowing a flagged question). Ledger row
  pending: the actual fix (rebuilding `MinimalistStripView` as true
  badge/bubble composition) is being routed through a standalone PR, not a
  reopened phase-14 ticket — the review-gap ledger row will be appended once
  that PR's fix commit lands, citing it as `fixCommit`.

### `staleness-cta-gated-on-proxy-not-true-predicate`
- **Seen:** 1× — `codogotchi-27` (P8). The lockstep "Hooks are out of date —
  click Update" banner was gated on `bundledVersion != installedVersion`. That
  version string is a *proxy* for the real condition ("the installed hook
  registration differs from what we'd write now"): it also moves on
  binary-internals-only bumps (c52a5bb0, the 1.0.0->1.0.1 hook-binary bump) that
  change nothing on disk, so Update would rewrite byte-identical config. The true
  predicate was already computable — `hooks status` exposed per-platform wiring
  (`installed`/`partially_installed`) — but the banner reached past it to the
  weaker version comparison. Fix added a `registration_current` fingerprint the
  banner keys on instead; version drift is now silent.
- **Proposed clause:** *"For any banner/CTA that tells the user something is
  stale, broken, or out-of-date and offers a fix button, the gate must be the
  narrowest TRUE predicate for the action that button performs — not a broader
  proxy (a version string, a timestamp, a build id, an mtime) that can move
  without the fixable condition changing. Ask: can this proxy differ from
  'the fix would actually change something'? If yes, the CTA fires no-op work
  and trains the user to ignore it. Corollary: if the system already computes
  the true condition elsewhere (here `hooks status` registration wiring),
  reaching for a proxy is the smell."*
- **Relationship to existing candidates:** same proxy-vs-truth root as
  `time-based-feature-tested-against-proxy-condition` (codogotchi-19), but the
  divergence surfaces at the *trigger of a user action* rather than in a test's
  scenario fidelity; and a cousin of
  `control-signal-starved-by-change-gated-callback` (a signal riding the wrong
  condition). Possible future merge into a broader
  `proxy-condition-substituted-for-true-predicate` family if a third proxy-vs-
  truth instance lands on another surface.
- **Caveat that blocks naive promotion:** classified `review-reachable` here
  because the true signal already existed in the same subsystem, making the
  proxy visible as a proxy at review time — but that "true signal was already
  present" evidence may not hold for every instance of the class, so confirm
  demonstrability before promoting.
- **Status:** WAITING — single instance. Needs ≥1 more occurrence (ideally a
  non-menubar surface) to confirm the class and settle standalone vs. merge into
  a proxy-condition family.

### `adjacent-consumer-of-changed-key-shape-missed-across-file-boundary`
- **Seen:** 2× — `codogotchi-30` (P15 QC). Phase 15 introduced session-keyed
  window keys (`origin:session_id`) and shipped the plumbing to render them as
  a friendly label (`SessionLabelStore` custom rename, `SessionNumberAllocator`
  ordinal) wired into the per-window session badge/tooltip
  (`FloatingPetController`, commit `d99a7e19`). `MenubarMenu.displayName(for:)`
  — a pre-existing, untouched platform-name switch in a completely different
  file — already consumed the same window-key strings (via
  `activeOrigins`/`hiddenWindowKeys`) but was never updated to recognize the
  new session-keyed shape, so it fell through to its default case and
  title-cased the raw session UUID straight into the "Hide X Pet" menu item.
  `codogotchi-31` (P15 QC, same round): a second, distinct consumer of the same
  session-fanout dimension — `AttentionBubbleView`'s Focus and X affordances,
  which predate session-pets (phase-06, ticket-02) and live in
  `AttentionBubblePanel.swift`/`MenubarApp.swift` — were never revisited when
  ticket-04 (phase-15) started spawning one window per active session for the
  same origin. Both actions funneled into the P15.04 session-precise
  `dismissAttention(origin:sessionId:)` write, which is correct for Force Idle
  but wrong for Focus: `NSWorkspace.activate()` can only foreground the
  platform app as a whole, never one specific thread, so every sibling
  session's bubble for that origin should have been treated as handled too.
  Same failure shape as `codogotchi-30` — an old, unrelated file's assumption
  ("one window per origin" / "acting on this key only affects this key") never
  re-derived after phase-15 multiplied windows per origin — but the consumer
  here is a user action/callback wiring, not a display formatter.
- **Proposed clause:** *"When a ticket changes the SHAPE of a shared key or
  identifier (adds a delimiter, a new segment, a new encoded dimension),
  grep the whole codebase for every consumer of that key — not just the
  consumers touched by this ticket's diff or visible in the same subsystem —
  and confirm each either handles the new shape correctly or is explicitly
  out of scope. A consumer in an unrelated file that predates the key-shape
  change is invisible to a same-diff review and will silently mis-render the
  new shape (title-casing a UUID, mis-parsing a delimiter, truncating a new
  segment) until someone dogfoods that specific surface."*
- **Relationship to `new-enum-case-skips-existing-transition-matrix`:** same
  root failure mode as the `codogotchi-06`/`-28`/`-29` family (an old
  assumption not re-derived after a dimension changed) but a different
  manifestation and a different lever. That family is reactive *teardown
  branches inside the same pool file* (review-reachable once you know to look
  at that file's transition matrix); this class is *a consumer in a
  completely different file, with no shared diff, that predates the
  key-shape/plurality change* — `codogotchi-30`'s was a display formatter,
  `codogotchi-31`'s was a user-action callback (Focus/dismiss), so the class
  is not limited to rendering. No reviewer looking at the phase-15
  session-fanout tickets would have had either file in view. This is why it
  classifies `qa-gap`, not `review-reachable`: the fix requires enumerating
  consumers codebase-wide, not re-reading one file's branches.
- **Status:** WAITING — 2 occurrences, both in the menubar app and both
  triggered by the same phase-15 session-fanout dimension. Needs ≥1 more
  occurrence (ideally a non-menubar or non-session-key surface) to confirm the
  class generalizes and settle whether the clause belongs in the review prompt
  (as a "grep all consumers" step) or a phase-integration/dogfood checklist
  item, mirroring the same review-prompt-vs-integration-pass split left open
  for `compound-widget-cohesion-under-transform` and
  `control-signal-starved-by-change-gated-callback`.

### `existing-escape-hatch-action-not-extended-to-newer-adjacent-ui-state`
- **Seen:** 1× — `codogotchi-33` (Force Idle predates the SOA ticket/gate
  badge and the P15.08 conflict `SpeechBubblePanel`; its right-click handler
  only ever rewrote the `state.d/` activity slice, and neither newer
  stuck-state indicator was revisited to fold into the "clear this stuck pet"
  affordance when it was added).
- **Relationship to `codogotchi-30`/`codogotchi-31`'s session-fanout family:**
  same root shape — an old action/consumer, written before a later feature
  landed, never re-derived against the new state — but a different trigger.
  The session-fanout family is triggered by a *key-shape/plurality* change
  (one window per origin becoming many). This one is triggered by *new
  parallel UI state being layered onto an existing pet* (a badge, a bubble)
  with no shared diff against the original escape-hatch action, so a reviewer
  of the newer feature's ticket would have had no reason to open
  `MenubarApp.swift`'s Force Idle wiring.
- **Proposed clause (tentative):** *"When adding a new persistent per-pet UI
  indicator (badge, bubble, overlay) driven by state outside the pet's core
  activity slice, grep for every existing 'reset/clear/dismiss' affordance on
  that pet and confirm whether the new indicator should be folded into it. An
  escape hatch's users assume it clears everything visibly wrong with the
  pet, not just the specific field it was originally scoped to."*
- **Status:** WAITING — only 1 occurrence so far. Needs ≥1 more (ideally a
  non-Force-Idle, non-menubar surface) before deciding whether to fold into
  the session-fanout family above or promote as its own class.

### `hide-toggle-conflated-with-pool-slot-release`
- **Seen:** 2× — `codogotchi-38` and `codogotchi-39` (both phase-15 QC, same
  dogfooding session, same file). `codogotchi-38`: `FloatingPetWindowPool`'s cap
  incumbency (`SessionSelectionPolicy.select`'s `currentlyRendered` input) was
  derived from `windows[$0] != nil` — a reasonable local implementation when
  P15.07 (cap selection) shipped, since at the time every window teardown really
  did mean "this session lost its place." The phase-15-QC hide/show feature
  later added a second, independent reason a window can disappear (`setVisible`
  concealing it on user request) without revisiting that assumption, so hiding
  an incumbent silently read as a freed cap slot and a pending idle sibling
  backfilled it in the hidden pet's place. `codogotchi-39`: fixing `-38`
  exposed the very next layer of the same shared-state problem — once hide
  stopped forfeiting a slot on conceal, nothing was defined for what happens
  to the hidden flag when the session is later GENUINELY evicted (a real
  in-flight newcomer, not a bogus backfill). `MenubarMenu` enumerates only
  `activeOrigins union hiddenWindowKeys`, with no third "hidden, but now just
  cap-pending" state, so a genuinely-evicted hidden session left a dead "Show"
  menu entry and then vanished from both sets entirely once clicked — found
  by the developer walking the `-38` fix one scenario further, live, in the
  running production app.
- **Proposed clause:** *"When a pool/registry derives ANY policy decision
  (eviction, incumbency, promotion, numbering) from whether an item currently
  has a live resource (a window, a connection, a handle), enumerate every
  action that can tear down that resource for a reason OTHER than the policy's
  own decision (a user-visibility toggle, a mode switch, an unrelated teardown
  branch) and confirm the policy either ignores those or is explicitly told
  about them. Resource-existence is not intent — a second feature added later
  that manipulates the same resource for an unrelated reason will silently
  corrupt the policy's assumption without touching the policy's own code."*
- **Relationship to `user-hide-overwritten-by-periodic-respawn`:** same family
  (hide/pool-state interaction bugs recurring in this exact file across
  phases: `codogotchi-21`, `codogotchi-36`, now `codogotchi-38`), but a
  different manifestation — that class is about the hide flag not surviving a
  refresh boundary; this one is about a DIFFERENT piece of pool state (cap
  incumbency, not visibility) silently reading window-teardown as a policy
  signal. Also a cousin of `pool-spawn-position-not-per-origin` (per-owner
  state assumptions breaking under a pool refactor) and the
  `new-enum-case-skips-existing-transition-matrix` family (an old assumption
  not re-derived after a later feature added a second way to trigger it).
- **Caveat that blocks naive promotion:** both occurrences are in the same
  file, same feature (hide/show), same dogfooding session, and the second was
  found by directly extending the first's fix rather than an independent
  discovery — so this is closer to "one bug fixed in two passes" than two
  unrelated recurrences. `FloatingPetWindowPool` is clearly a hotspot for this
  general shape of bug regardless (5 related ledger rows total across phases),
  so the file itself may warrant a standing "re-audit every `windows[$0] !=
  nil` / `windows.keys` read, and every menu-enumeration set, whenever a new
  window-teardown or visibility-toggle trigger is added" checklist item.
- **Status:** AT 2× WITHIN ONE FILE — strong signal the *file* needs a
  standing integration checklist (enumerate every consumer of `windows`,
  `slotOccupants`, and `userHiddenWindowKeys` together whenever any one of
  them gains a new writer), but still wants ≥1 cross-file or cross-repo
  instance before promoting a generic review-prompt clause — both instances so
  far were only reachable by live dogfooding, not diff review, since each
  fix's own diff was locally correct and the gap was in the *unstated*
  interaction between fixes.
- **Unrelated finding, not part of this class:** while dogfooding `-39` live,
  the developer also hit a `CODOGOTCHI_HOME`-vs-`HOME` inconsistency in
  `DemoConfig.from` (`apps/menubar/Sources/DemoConfig.swift`) — it only checks
  the plain `HOME` env var for `pollingTarget`, while every other config path
  (`CodogotchiFolders`, `AppState`, `PetConfig`) checks `CODOGOTCHI_HOME`
  first. This made a supposedly-isolated dev sandbox instance silently poll
  the developer's real `state.d/`. No ledger row filed for this (dev-tooling
  gap, not a shipped-behavior defect — production always runs with a single
  `HOME`), but worth a small standalone fix if sandboxed manual testing of
  this app becomes routine.
- **Unrelated finding, not part of this class:** while dogfooding the P18.05
  pre-cutover shadow soak checklist live, the developer noticed an occasional
  small delay in the Combined → Own/Minimalist panel transition. Not
  reproduced as a hard defect (everything else in the checklist checked out),
  no ledger row filed, no fix attempted — flagged here only so a future pass
  has a pointer if it recurs or turns out to matter more than a cosmetic
  frame or two of transition lag.

### `protocol-default-noop-swallows-adapter-forward`
- **Seen:** 1× ledgered — `codogotchi-46` (P19 mode chip). Same shape already
  documented in-tree by `MinimalistWindowControllerTests.testForwardsSessionLabelAndTooltipToPanel`
  (P15.06 session-label forward), which predated this ledger class.
- **Proposed clause:** *"When a push protocol adds a new `apply*` member with a
  protocol-extension default no-op, enumerate every adapter between the pusher
  and the leaf renderer (window controller → panel, pool stub → real panel) and
  require an explicit forward plus a regression that asserts the leaf received
  the value. Default no-ops make missing forwards compile and let outer-stub
  unit tests stay green while production silently drops the push."*
- **Status:** WAITING — single ledgered instance; promote after ≥1 more
  occurrence (or treat the P15.06 regression comment as the second sighting
  once that older gap is backfilled into the ledger).

### `unconditional-directory-listing-trusts-externally-populated-tree`
- **Seen:** 1× — `codogotchi-40` (attributed to phase-11, gallery/marketplace,
  where the Codex-import listing shipped). `PetTabViewModel`'s Codex-pet
  enumeration (`directoryNames(in:)` over `~/.codex/pets`) trusted every
  subdirectory as a pet, tolerant of a missing/malformed `pet.json` by design
  so genuine pets with slightly off manifests still got a thumbnail attempt.
  That tolerance meant a directory belonging to an entirely different feature
  — `.hatch-runs`, a scratch/run-log location the hatch spritesheet pipeline
  writes into the same `~/.codex/pets` tree — rendered as a bogus importable
  pet card with a fabricated display name and a dead spritesheet link. Found
  only by the developer looking at their real, long-lived `~/.codex/pets`
  directory in the running app; no test fixture in the suite had ever
  populated that directory with anything other than valid pets.
- **Proposed clause:** *"When a feature enumerates a directory (or other
  namespace) that is populated by an EXTERNAL or UNRELATED process — not
  exclusively by this feature's own writer — validate each entry against the
  feature's actual shape contract (required fields present, referenced
  resource exists) before treating it as a first-class item, rather than
  trusting 'is a directory' / 'exists' alone. A missing-file fallback that's
  correct for a slightly-malformed instance of the target type is NOT the
  same guarantee as excluding instances of a completely different type."*
- **Relationship to `hide-toggle-conflated-with-pool-slot-release`/
  `side-effect-call-dropped-or-mis-targeted-in-refactor`:** a different root
  cause (no refactor or second feature touched this code path — the
  vulnerability was present at initial ship) but the same detection lever:
  only reachable by dogfooding the real, organically-populated filesystem
  state, not by diff review or the existing test suite, since test fixtures
  universally control their own directory contents.
- **Caveat that blocks naive promotion:** single instance, and the "external
  process pollutes a shared directory" precondition is narrower than most
  promoted classes — it requires two unrelated features to share exactly one
  filesystem namespace (here, `~/.codex/pets` is both the Codex-pet source of
  truth AND the hatch pipeline's scratch location). Needs ≥1 more occurrence,
  ideally in a different shared-namespace pairing, before promoting a
  standing review-prompt clause.
- **Status:** WAITING — single instance. Worth flagging early because the
  "trust every directory entry" shape is easy to reintroduce anywhere the app
  enumerates a filesystem location it doesn't exclusively own (gallery
  install dirs, hook directories, per-platform state.d roots).

### `overlay-defers-host-chrome-refresh-until-dismiss`
- **Seen:** 1× hard recurrence chain — `codogotchi-25` introduced the
  persistent assign `NSPopover` that only rebuilt pet-card badge pills in
  `popoverDidClose`; `codogotchi-47` is the dogfood gap where floating-panel
  live-swap updated immediately on toggle but card logo pills / Default border
  stayed stale until click-away.
- **Proposed clause:** *"When a transient overlay (popover/menu/sheet) mutates
  shared model state that already drives other live surfaces, enumerate every
  host chrome element that mirrors that state (pills, borders, badges, counts)
  and refresh it on each mutation — not only on overlay dismiss. Dismiss-time
  rebuild is fine for structural layout, not for assignment/selection feedback
  the user expects to see while the overlay stays open."*
- **Caveat that blocks naive promotion:** mostly `qa-gap`-flavored; the
  dismiss-gated rebuild was intentional and left an explicit comment. Not a
  clean adversarial-review hit unless the ticket already promised live host
  chrome (as P14.08 did for floating-panel live-swap but not card pills).
  Promote only if a second unrelated overlay shows the same "live elsewhere,
  stale under open overlay" split.
- **Status:** WAITING — paired with `codogotchi-25` as origin; needs ≥1 more
  independent occurrence before a standing UI-review clause.

### `successor-badge-leaves-redundant-menu-disambiguation`
- **Seen:** 1× — `codogotchi-48` (P19.03 expanded Prune with
  `"(platform · label)"` for folds; P19.04 added mode/session badges that
  already show that identity, but the menu formatter kept expanding).
- **Proposed clause:** *"When a later ticket in the same phase (or a follow-on
  ticket) adds durable on-panel chrome that owns an identity or disambiguation
  job previously done by menu/alert copy, revisit every formatter that still
  interpolates that identity. Prefer retiring redundant parentheticals once
  the live badge/chip is the source of truth."*
- **Caveat that blocks naive promotion:** completeness-/planning-flavored,
  not a clean adversarial-review miss inside a single ticket diff. Needs a
  second "ticket A invents copy disambiguation → ticket B adds chrome →
  copy not retired" occurrence before promoting a standing phase-sequencing
  check.
- **Status:** WAITING — single instance tied to phase-19 badge follow-through.

### `sibling-surface-misses-new-promotion-limb`
- **Seen:** 1× — `codogotchi-51` (phase-19 QC: Settings Show All Live vs
  menubar Show … Panel for sessions-off Live rows).
- **Proposed clause:** *"When a ticket teaches one UI surface a new promotion
  / un-hide path for fold or sessions-off panels (especially when
  `canShow == false` rows are intentionally excluded from per-row Show),
  enumerate sibling bulk actions on other surfaces (Settings Sessions,
  Show All Pets) that claim to act on the same Live set and require them to
  share the new limb or document why they stay narrower."*
- **Caveat that blocks naive promotion:** completeness-/planning-flavored —
  the menubar diff alone does not force a reviewer to open
  `SessionsTabViewModel.showAllLive`. Needs ≥1 more
  "surface A gains promotion path → surface B bulk twin left on old gate"
  occurrence before promoting.
- **Status:** WAITING — single instance from phase-19 panel-affordance
  follow-through.

### `sibling-method-skips-a-key-resolution-step-a-neighbor-already-takes`
- **Seen:** 1× ledgered — `codogotchi-52` (phase-16, resolved phase-19 QC).
  `SessionsTabViewModel.show(key:)`/`hide(key:)` already resolve a row's
  slice-derived `WindowKey` through `pool.renderedWindowKey(for:)` before
  touching the pool, because a sessions-off fold winner's own key is never
  the pool's actual render-target key. Three sibling methods in the *same
  file* — `pruneActive`/`pruneAllActive`/`pruneAllSessions` — pass the raw
  `row.id` straight into `pool.pruneSession` instead, from the moment
  `pruneActive` was introduced (P16.05) alongside the very fold-resolution
  machinery `show`/`hide` correctly use a few methods away. Same recurring
  shape as `codogotchi-40`/`41` (a caller/callee `WindowKey`-space mismatch
  on the Prune path specifically) but a different manifestation — that pair
  fixed the mismatch *inside* `pruneSession`; this one is in the caller,
  one layer out, in methods that had a correct sibling to copy from and
  didn't.
- **Proposed clause:** *"When a class has multiple methods that resolve the
  same ambiguous identifier (a raw key, an unqualified id) before handing it
  to a shared lower-level API, and at least one of those methods already
  performs a resolution step (`renderedWindowKey(for:)`, a canonicalization
  call, an identity lookup), audit every sibling method touching the same
  lower-level API for the identical step — do not assume a method 'looks
  simple enough' to skip what a neighboring method needed. The presence of
  a correct example in the same file is not protection; it is only found by
  deliberately diffing the sibling methods against each other, not by
  reading either one in isolation."*
- **Relationship to `side-effect-call-dropped-or-mis-targeted-in-refactor`:**
  a cousin — both are "an old assumption not re-derived / re-applied
  elsewhere" — but that class is triggered by a REFACTOR moving/replacing an
  owner; this one has no refactor trigger at all. The correct and incorrect
  methods were written at the same time, in the same commit (P16.05), with
  no later change disturbing either — this is a same-commit oversight, not
  drift introduced by a later change.
- **Caveat that blocks naive promotion:** single ledgered instance. The
  "audit sibling methods against each other" lever is a strong completeness
  check but expensive to apply universally (every class with >1 method
  touching a shared lower-level API) — needs ≥1 more occurrence to judge
  whether it is narrow enough (e.g. "specifically WindowKey resolution
  before a pool call") to state as a targeted clause, or too broad to be
  actionable as written.
- **Status:** WAITING — single instance. Promote only after a second
  same-file "sibling method skips a resolution step a neighbor already
  takes" occurrence, ideally on a different key/identifier shape than
  `WindowKey`.

### `fold-winner-promotion-blocked-by-recency-only-election-and-cap-policy`
- **Seen:** 1× — observed while scoping a phase-19 QC ask (Sessions panel Live
  rows should offer Show, not just Prune, and Show should be able to promote a
  non-winning sibling into the active slot). No fix attempted; no ledger row.
- **Observation (not yet a fix — deferred):** `SessionsTabViewModel.canShow`
  and `showAllLive`'s off-`canShow` promotion branch both explicitly treat
  "Show a non-winning Live sibling whose fold target already has an active
  winner" as unsupported — `canShow`'s own comment calls it a no-op that
  "cannot be surfaced without changing winner election," and `showAllLive`
  bails via `guard !pool.activeOrigins.contains(target) else { continue }` the
  moment a winner is already active. Making Show actually promote such a row
  (demoting the previous winner to Live) is not a bounded fix for two
  independent reasons: (1) winner election reads as purely recency-based
  (freshest `updated_at` wins), so naively bumping the target's `updated_at`
  via `refreshForShow` risks being immediately re-flipped back by the demoted
  winner on the very next poll tick if that winner is itself still genuinely
  live — an explicit user Show needs to be durable against that, which likely
  wants a real pinned-winner override rather than a timestamp trick; (2) the
  same promotion has to interact correctly with the existing Session Cap /
  "Evict Session Pets" policy when sessions-enabled is ON and the platform is
  at capacity — Show may need to trigger eviction of a different session's
  window, not just win a recency race. These are two separate policies (fold
  promotion when sessions are off vs. cap-aware eviction when sessions are on)
  that no current code path unifies.
- **Relationship to `sibling-surface-misses-new-promotion-limb`:** same code
  path (`SessionsTabViewModel.canShow`/`showAllLive`), same phase-19
  promotion-affordance thread — that class is the narrower "surface A vs
  surface B parity" framing; this is the deeper "can Show ever override an
  existing winner at all" question underneath it.
- **Status:** WAITING — no ledger row, no fix attempted, developer explicitly
  declined `/soa plan` or a follow-up task for now. Flagged here as a pointer
  for whenever fold-winner/session-cap interaction work is prioritized —
  needs product-level design (pinned-winner mechanism, cap-aware eviction
  rules) before any implementation.

### `vestigial-schema-field-mechanically-round-tripped-past-its-consumer`
- **Seen:** 1× — `codogotchi-49`/`codogotchi-50` investigation (phase-13/15 QC
  fix for `floating_pet_positions`/`floating_pet_hidden` pruning).
- **Observation (not yet a fix — deferred, no ledger row):** `app-state.json`'s
  singular `floating_pet` field (schema-v3 `AppStatePayload.floatingPet`,
  introduced phase-4 P4.02 before per-origin/per-session windows existed) is
  still read and written on every `AppStateStore.load`/`save`, but no live pool
  window (`FloatingPetController`/`MinimalistWindowController`) is ever
  constructed from its `visible`/`frame` values — every real window goes
  through the per-origin `loadFrame`/`saveFrame` path instead (added P13).
  `save()`'s only real caller (`refreshHookStatusCache`) round-trips the field
  unchanged. It compiles, decodes, and encodes cleanly, so nothing flags it.
- **Proposed clause:** *"When a later phase adds a per-key/per-scope
  replacement for a singular top-level state field (single-window →
  per-origin, global flag → per-session map), check whether the original
  field still has a live reader that actually drives behavior, or whether it
  now only survives via a self-preserving round-trip in an unrelated save
  path. A field that decodes/encodes without error can still be dead weight —
  compiler and schema-fixture tests can't catch 'unused' the way they catch
  'malformed'."*
- **Caveat that blocks naive promotion:** single instance, and the fix
  (removing a non-optional schema field, deciding v4 migration handling) is
  larger/riskier than a bounded QC fix — deliberately deferred rather than
  bundled into `codogotchi-49`/`codogotchi-50`. Needs a second occurrence
  (or a scoped removal ticket) before promoting past this candidate stage.
- **Status:** WAITING — no ledger row yet (observation, not a verified fix);
  candidate future ticket: remove `floating_pet` from `AppStatePayload` and
  decide the v3→v4 migration/back-compat story.

## Open meta-question (for the eventual `/soa quality-control` skill)

The 7 existing diff-derived classes are backend/CLI-shaped. codogotchi's
post-phase fixes are overwhelmingly UI/interaction/animation. Likely upstream
finding once evidence accumulates: UI-heavy SoA repos need a **parallel
UI-review class family** — gesture state-machine integrity, animation-frame
continuity, screen-space vs view-space coordinate bugs, compound-widget cohesion,
affordance hit-testing. Hold until the ledger has enough rows to name the cut.
