# Phase 02 — macOS Menu Bar Pet retrospective

Source plan: [`docs/product/plans/phase-02.md`](../plans/phase-02.md).
Delivery plan: [`docs/product/delivery/phase-02/implementation-plan.md`](../delivery/phase-02/implementation-plan.md).

## Scope delivered

Tickets P2.01 → P2.11 (11/11) shipped as a stacked PR chain on
`agents/p2-*` branches, PRs
[#26](https://github.com/cesarnml/codogotchi/pull/26) through
[#36](https://github.com/cesarnml/codogotchi/pull/36). Delivered:
`apps/menubar/` Xcode project skeleton with TS-only `bun run ci`
preserved and `mac:build` / `mac:test` shelling out to `xcodebuild`;
`StateJsonReader` with closed-enum `ActivityState`, `schema_version`
forward-compat policy (accept `≤`, refuse `>`), and unknown-state →
`idle` fallback; `MaliPet` asset loader with a hardcoded
`[ActivityState: RowSpec]` table loading WebP via `NSImage`/`CGImage`;
`MenubarRenderer` driving `NSStatusItem` with the continuous-loop
animation policy (1 s/cycle, infinite, swap on transition); demo mode
behind `CODOGOTCHI_DEMO=1` / `--demo` writing fixtures to
`$TMPDIR/codogotchi-demo/state.json` on a 3 s cycle; live polling at
1 s against `~/.codogotchi/state.json` with three explicit failure
visuals (missing/unreadable, schema mismatch, stale → idle);
`TransitionLog` NDJSON writer at `~/.codogotchi/state-transitions.log`
with per-state events + hourly heartbeat + 10 MB / single-backup
rotation matching `sync.log`; menu with **Quit** and **Open log
folder** only, tooltips wired to failure states; sleep/wake observer
on `NSWorkspace.shared.notificationCenter` and run instructions
folded into `apps/menubar/README.md`; the
[`docs/contracts/animation-state-vocabulary.md`](../../contracts/animation-state-vocabulary.md)
forward-compat clause; eight `notes/private/phase-02-swift-notes/`
companion docs (P2.03–P2.10) plus this phase's curated `INDEX.md`.

## What went well

- **Demo mode landed before live polling and paid for itself.** P2.06
  put a sandboxed `$TMPDIR/codogotchi-demo/state.json` cycle driver in
  front of `MenubarRenderer` so all four floor states were proven to
  render correctly from fixtures before P2.07 ever pointed at the real
  hook output. The order made the Swift-correctness question
  ("does the renderer animate Mali for each `ActivityState`?")
  independent of the pipeline-correctness question ("does the hook
  emit the right state right now?"). That separation was the only
  reason P2.07 could ship as a thin wiring change instead of a
  multi-day Swift + hook debug spiral.
- **Hardcoded `[ActivityState: RowSpec]` table in Swift was the right
  Phase 02 shape.** P2.04 deliberately did not extend `pet.json` or
  add a sibling `codogotchi-rows.json`. The row-map lives in
  `MaliPet.swift`; the pet-format contract stays exactly what
  Phase 01's hook emits. That decision means Phase 06 (multi-pet
  catalog) inherits a clean question — "what does a pet-format
  extension look like when it has multiple consumers?" — instead of
  inheriting an extension that exists only for Mali.
- **Continuous-loop animation policy survived without revision.**
  Phase 02's `Grill-Me decisions locked` block called the divergence
  from Codex's one-shot burst pattern out explicitly: codogotchi
  polls every second, so a 3-cycle burst would either drop frames or
  fight the poller. The decision held through five Swift tickets
  (P2.05–P2.09) without anyone wanting to revisit it; the renderer
  swap-on-transition implementation is small enough to read in one
  sitting because it never had to grow special-case burst code.
- **Pure 1 s polling beat `DispatchSource` / `FSEvents`.** The plan's
  "simplest possible thing" stance held under real Swift implementation.
  `LivePollingDriver` is a `Timer.scheduledTimer` with a `[weak self]`
  closure; the entire watch loop fits on one screen. Energy concerns
  were explicitly deferred to a later distribution phase, which let
  Phase 02 ship without rationalizing them away. Future tuning has a
  cheap surface to touch.
- **`subagentReview: skip_doc_only` + `prReview: disabled` kept the
  closeout cycle fast.** With external AI review explicitly disabled
  for this phase (gated mode, `prReview: disabled`), each ticket's
  review window collapsed to the subagent gate plus the operator's
  own diff read. Doc-only tickets (P2.02, P2.11) flowed through with
  `subagent-review` auto-recording `skipped`. Code tickets that
  surfaced honest findings (P2.01) used a `[subagent-review]` patch
  commit and stayed on the orchestrator path without a separate
  `record-review` cycle.

## Pain points

- **(Avoidable waste) "ci stays TS-only" was reversed mid-phase.**
  P2.01's locked toolchain seam decision said the Swift gate would
  stay manual and owner-attested. During the P2.04 → P2.05 window
  the orchestrator's `post-red` step started silently accepting
  Swift compile failures because they did not show up in `bun run
  ci`; the fix was [`27159b6 chore(ci): include mac:test in ci so
  Swift red commits gate orchestrator post-red`](https://github.com/cesarnml/codogotchi/commit/27159b6),
  which chains `mac:test` into `ci` and `ci:quiet`. The result is
  good — Swift regressions now gate `post-red` and `open-pr` the
  same way TS regressions do — but the locked Grill-Me decision was
  overturned without an explicit Grill-Me revision. The `phase-02-as-shipped.md`
  doc captures this as a material divergence so Phase 03 planning
  reads the truth, not the original lock.
- **(Avoidable waste) Multi-worktree `reviews/` and `handoffs/`
  reconciliation, again.** Same shape as the Phase 01 retrospective
  flagged: each ticket worktree only sees the immediate-predecessor
  artifacts, so the `main` checkout needs a manual mirror sweep
  before `closeout-stack`. Phase 02 hit it again at P2.11; the
  follow-up bullet from the Phase 01 retrospective ("aggregate
  `reviews/` and `handoffs/` mirroring into a single helper") is
  still the right next step.
- **(Expected cost) Eight TS-developer Swift notes were real
  per-ticket overhead.** Each Swift-touching ticket (P2.03–P2.10)
  landed a `notes/private/phase-02-swift-notes/P2.NN-*.md` companion
  in the same PR. The discipline was correct — there is real Swift
  knowledge in those notes that does not live elsewhere in the
  repo — but writing them honestly was 10–20% of the ticket cost.
  Phase 03's floating-window + SpriteKit work will face the same
  tax; the notes are the artifact, not a deferred-able write-up.
- **(Expected cost) Xcode-native resources mean the `.xcodeproj`
  is a load-bearing committed binary.** `LSUIElement=true`,
  entitlements, and resource bundling all live inside
  `apps/menubar/Menubar.xcodeproj`. Diff review of project file
  changes is genuinely hard — there is no good text-diff story for
  `project.pbxproj`. P2.01 set the stance ("reviewers may not delete
  the `.xcodeproj`") and it held, but every Xcode-touching ticket
  needed a careful manual diff scan because biome / cspell cannot
  see those files.

## Surprises

- **`NSStatusItem` does not retain itself.** Documented in the P2.05
  Swift notes as the load-bearing oddity of that PR. The system
  status bar registers your `NSStatusItem` but does not keep it
  alive; the moment your last strong reference disappears, the icon
  vanishes from the menu bar. `MenubarApp` keeps a `var statusItem:
  NSStatusItem?` for exactly that reason. TS analogue: there is no
  TS analogue — JavaScript GC does not pull DOM nodes out from under
  you when their last reference disappears.
- **Two `NotificationCenter` instances, not one.** P2.10 surfaced
  this when the wake-from-sleep observer needed
  `NSWorkspace.shared.notificationCenter` rather than
  `NotificationCenter.default`. Registering wake notifications on
  the default center is a silent no-op; the names look correct but
  the events never fire. Captured in
  [`P2.10-lifecycle-hardening.md`](../../../notes/private/phase-02-swift-notes/P2.10-lifecycle-hardening.md)
  so the Phase 03 floating-window work does not re-discover it.
- **`Data.write(.atomic)` and the hook's tmp-rename pattern are the
  same race-free primitive.** Demo mode (P2.06) writes fixture state
  with `.atomic`; the Phase 01 hook writes real state with
  tmp-then-rename. Both are filesystem-atomic-on-the-same-volume.
  That symmetry was not designed in advance — it fell out of
  matching the hook's behavior — but it means the menu bar app's
  reader semantics (open + parse, never mid-write) are exercised
  identically in demo and live modes.
- **The animation-state-vocabulary forward-compat clause was used
  zero times in Phase 02.** P2.02 landed the renderer-must-refuse
  policy for `schema_version > expected` before any Swift code
  consumed it; nothing in Phase 02 bumped `schema_version`. The
  clause exists for Phase 03+ — it is a future-Swift-safety net,
  not a Phase 02 mechanism. Recording this so the next agent does
  not assume the policy is unproven; it is unexercised by design.

## Phase 01 patches surfaced during live use

**None.** No Phase 01 pipeline issues were surfaced by Phase 02 live
integration (P2.07–P2.10) or by post-implementation use during the
P2.11 retrospective window. The only Phase 01 patch that landed on
`main` between Phase 01 closeout and Phase 02 start was
[PR #24 — `fix(engine): skip decay for fresh profiles with null
last_signal_at`](https://github.com/cesarnml/codogotchi/pull/24),
which merged at 2026-05-20T10:26Z — roughly seven hours **before**
P2.01 started (2026-05-20T17:18Z). That patch is a Phase 01
closeout follow-up surfaced by the validation window described in
the Phase 01 retrospective's "Net assessment" section, not by
Phase 02 menu bar use. The phase-02 plan's Exit Condition #7
("Any Phase 01 pipeline issues surfaced by live use have been
patched on `main` before Phase 03 opens") is therefore satisfied
trivially — there is nothing to patch.

## What we'd do differently

- **Land the Xcode-CI question explicitly before Phase 03.** P2.01
  punted on "Swift in CI" with the toolchain seam decision; that
  was correct for a single-app phase, but Phase 03 adds a floating
  window + SpriteKit on top of the same project. A second Swift
  surface without an automation gate doubles the regression
  exposure. The right move is a one-off "should Phase 03 require
  a hosted macOS runner with Xcode, or stay with owner-attested
  Swift verification?" decision, made before Phase 03 ticket
  decomposition, not absorbed into a Phase 03 ticket.
- **Author at least one Swift note mid-ticket, not at PR-open.**
  The Phase 02 pattern was to write the swift-notes doc at the end
  of implementation alongside the green commit. That works but
  loses the surprises that were genuinely surprising during
  implementation — by the time the note is written, the surprise
  has been internalized and the prose flattens. Phase 03's
  AppKit / SpriteKit surface has more discoverable surprises;
  capturing them mid-ticket would make the notes more useful as
  reading material for a future agent.
- **Re-open Grill-Me when a locked decision needs to change, instead
  of patching it inline.** The "ci stays TS-only" lock was reversed
  in a single `chore(ci):` commit during P2.04/P2.05 to unblock
  `post-red` against Swift `[red]` commits. The fix was correct in
  outcome but bypassed the decision-change discipline that Grill-Me
  exists for. A 15-minute Grill-Me revisit at the moment the
  conflict surfaced would have produced the same outcome with a
  paper trail and probably caught the broader question (do
  Phase 03's Swift surfaces also belong in ci?) before it lands as
  another inline patch. See [`phase-02-as-shipped.md`](../plans/phase-02-as-shipped.md)
  for the recorded delta.

## Net assessment

**Implementation complete; "kept it running" still requires owner
attestation.** Phase 02's stated goal was "put a living Codex/Claude
pet in the macOS menu bar that reacts visibly to the agent's state,
convincingly enough that the owner keeps it running all day." The
Swift surface is real — eleven tickets, eleven PRs, demo-mode and
live-polling paths both wired, sleep/wake hardened, transition log
NDJSON with rotation, three failure visuals implemented. Exit
conditions #1 (builds and runs without crashing) and #2 (demo mode
cycles four floor states) are demonstrably true from implementation
state. Exit conditions #3 (used across real working days), #4 (all
four floor states fired on real activity in
`state-transitions.log`), #5 (all three failure visuals observed by
deliberate trigger), and #6 ("kept it running") are **owner-attested
gates** that this retrospective records as the developer-accepted
artifact. Exit condition #7 (Phase 01 patches surfaced by live use)
is satisfied trivially — see the dedicated section above.

The phase parallels Phase 01's pattern: the build slice landed
cleanly on the orchestrator path; the empirical validation window
remains the owner's to run, and this retrospective is the documented
shortfall acceptance per the phase plan's exit framing. The honest
read is that Phase 02 *shipped its code*, and the question Phase 03
opens against is whether the menu bar pet stayed running through
days of real Claude / Codex activity, not whether the Swift compiled.

Of the five named risks: the "Swift learning ramp outweighs the
visible deliverable" risk was mitigated by demo mode landing before
live polling (P2.06 before P2.07), exactly as the risk table
predicted. The "Phase 01 pipeline issues surface during real use"
risk did not bite — no patches were needed. The "`state.json` schema
drifts" risk did not bite — `schema_version` stayed at the value
Phase 01 shipped. The "technically correct, emotionally dead pet"
risk is the open one: it cannot be resolved by code, only by the
owner running the app for working days and judging. The
"distribution friction" risk did not bite — running the Xcode dev
build was acceptable for the single-user phase.

## Follow-up

- **Owner runs the menu bar app across real working days.** Pointed
  at the real `~/.codogotchi/state.json`. Inspect
  `~/.codogotchi/state-transitions.log` after each day to confirm
  the four floor states are firing. Decide at the end of the
  validation window whether Phase 02 exit gates #3–#6 are
  satisfied, or whether a Phase 02 amendment is required before
  Phase 03 opens.
- **Trigger all three failure visuals deliberately.** Rename
  `~/.codogotchi/state.json` away (missing visual); write a payload
  with `schema_version: 9999` (newer-than-supported visual); stop
  the hook for >N seconds and confirm the renderer falls through to
  `idle` (stale path). Record observations in the owner's running
  notes; no required format.
- **Decide Phase 03's CI stance.** Before `/soa decompose` runs on
  Phase 03, name whether Swift surface gains a hosted Xcode CI gate
  or stays owner-attested. Do not absorb the question into a
  Phase 03 ticket.
- **Aggregate `reviews/` and `handoffs/` mirroring helper, still.**
  Carried forward from the Phase 01 retrospective's follow-up; not
  attempted in Phase 02. A `deliver mirror-to-primary` command or
  equivalent would remove the manual sweep step that both phases
  ran before `closeout-stack`.
- **Phase 03 inherits the `state.json` polling, transition-logging,
  and demo-mode patterns unchanged.** Protect them as the
  floating-window + SpriteKit work begins. The continuous-loop
  animation policy is the load-bearing assumption Phase 03 builds
  on; revisit only if SpriteKit forces a different cadence.

---

_Created: 2026-05-21. Phase 02 stack open in PRs #26–#36; closeout pending developer approval._
