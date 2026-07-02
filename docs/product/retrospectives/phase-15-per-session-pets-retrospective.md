# Phase 15 — Per-Session Pets (Pet Per Active Agent Thread) Retrospective

## Scope delivered

10 tickets, PRs [#150](https://github.com/cesarnml/codogotchi/pull/150) – [#158](https://github.com/cesarnml/codogotchi/pull/158) (P15.01–P15.09; P15.10 opens its own PR). Branch stack: `agents/p15-01-*` → `agents/p15-10-*` stacked on `main`.

- Contracts: `customization.json` gains `session_pets_enabled` / `session_cap` maps (`schema_version` unchanged — additive, already-tolerant)
- Refactor: three per-tick directory scans consolidated behind one `StateDirectoryListing.scan(at:)`, byte-identical, existing suite as regression net
- Swift: `StateJsonReader.readPerSessionDirectory` (per `origin:session_id` granularity) + pure `resolveRenderKeys` collapse (session-pets-off folds to last-writer-wins per origin, byte-identical to the pre-Phase-15 render set; session-pets-on keeps each session as its own key; combined folds to `"combined"`)
- Swift: `FloatingPetWindowPool` fans out one window per resolved render key instead of one per origin; pet identity/mode/badge resolution derives the owning origin from the key via one static helper
- Swift: `PlatformSessionBadge` + `SessionNumberAllocator`, an in-memory per-platform lowest-free-number allocator rebuilt at launch
- Swift: `SessionLabelStore` (`~/.codogotchi/session-labels.json`, app-owned sidecar) for ≤24-char rename via right-click → Rename Session; native `NSView.toolTip` surfaces each session's last prompt
- Swift: `SessionSelectionPolicy` (cap + priority eviction: idle/standby → errored → waiting_for_input → never auto-evict active), manual Prune Session (right-click, destroys slice + number + label immediately), session-keyed TTL
- Swift: `ConflictBubbleRateLimiter` + `ConflictBubbleTargetSelector` — a rate-limited bubble on the longest-lived panel when every remaining session is actively working, deep-linking to Settings
- Swift: Settings → **Platform Settings** (renamed from "Platform Display Mode") gains **Enable Session Pets** (interactive only for Own/Minimalist) and **Session Cap** (2–10, Unlimited, default 3)
- Docs, version bump to **2.2.0**, retrospective (this ticket) — no DMG cut this phase

Final CI baseline at phase start: 704 tests, 0 failures (`445ccb36`). By P15.09: 785 Swift tests green, including all Phase 15 red→green additions across all nine code tickets.

## What went well

**The composite-key collapse made per-session rendering additive, not a rewrite.** `resolveRenderKeys` folding to a byte-identical per-origin map when session-pets is off — asserted directly by `testAllDefaultCollapseEqualsPerOriginMap` and gated as a phase stop condition ("P15.03 must feed the pool a byte-identical per-origin render set... every existing `FloatingPetWindowPoolTests` case must still pass unchanged") — meant the entire existing pool test suite became the regression net for the new architecture instead of needing a parallel test track. The pool then widened its key-typed dictionaries to resolved render keys in one seam (`windowKey(for:)`) rather than adding a parallel `[origin: [sessionId: Window]]` map, which the ticket explicitly named as the anti-pattern to avoid (P15.04 rationale). This is the same "day-one architecture, not a migration" bet the Grill-Me pass locked before decomposition, and it held through six downstream code tickets without a single structural rework.

**Subagent review caught three real correctness bugs, not just style notes.** F-1 in P15.05 (`releaseSessionNumber` silently no-op for TTL-expired sessions, permanently leaking numbers under a bounded cap), the P15.06 finding (`AnimationBadgePanel.ignoresMouseEvents = true` blocked `NSView.toolTip` from ever firing — the rename tooltip was wired end-to-end but silently never displayed), and the P15.08 finding (`FloatingPetController`/`MinimalistWindowController` never overrode `applyConflictBubble`, so the pool's calls silently hit the protocol's no-op and the bubble never reached the screen) were all genuine, user-visible gaps that automated tests hadn't caught. Each was patched same-session with a `[subagent-review]`-labeled commit. This is the review process doing exactly the job it's designed for.

**Reversible de-render instead of delete kept the eviction model simple.** Cap eviction holds the excess session's on-disk slice and recomputes the top-N-by-priority partition every tick rather than deleting anything — so "promotion" needed no dedicated bookkeeping (P15.07 rationale: a session leaving `pending` "simply wins the next partition"). Only manual Prune and TTL expiry actually delete. This meant the selection policy is a pure per-tick recomputation with no separate promotion state machine to get wrong.

**Locking the sidecar-file boundary at grill-me time avoided a two-writer race.** `session-labels.json` was decided as Swift-owned (not routed through the CLI-writer `state.d` slice) before any code was written, because the slice's atomic full-overwrite would have clobbered a label written by the app. The same reasoning that produced `assignments.json` in Phase 14 generalized cleanly to a second sidecar file with no schema entanglement.

## Pain points

**The `subagentReviewOutcome` field in `state.json` undersells what actually happened.** All nine code tickets show `subagentReviewOutcome: "clean"` in the delivery state — including P15.05, P15.06, and P15.08, each of which has a real `[subagent-review]`-labeled fix commit for an actionable finding the runner surfaced. The true record lives in the git history (`[subagent-review]` commit subjects) and the `reconcile-subagent-review` audit trail ("reconciliation appended patched row" commits), not the headline field. A future reader trusting only `state.json` would conclude the review process found nothing three times when it actually caught three real bugs — undercounting the value the gate delivered.

**The negative-`sessionCap` normalization gap was flagged three separate times and never converted to a fix.** P15.05's subagent review noted it as advisory (`sessionCap` wasn't writable yet, so moot). P15.09 shipped the Settings UI that makes it writable — a negative value still isn't possible through the UI (the dropdown only offers 2–10/Unlimited), but a hand-edited `customization.json` with a negative `session_cap` still isn't clamped anywhere in the allocator. Three tickets deferred it as "someone else's problem" and it's still open at phase end.

**Minimalist mode's rename/tooltip parity gap is a real, acknowledged UX asymmetry.** P15.06 wired rename and last-prompt tooltip end-to-end for Own mode only; `MinimalistWindowController` inherits a no-op default for both, so a Minimalist session badge always reads "Session N" with no rename affordance. This was a deliberate scope call (2-point ticket, `MinimalistPanelManaging` protocol conformance would have doubled the UI-wiring surface) but it means the exit condition's "Flipping the platform to Minimalist swaps pet panels for badge strips carrying the same per-session labels" is not fully true yet — labels degrade to session numbers in Minimalist mode.

## Surprises

**`isLocalBranchDocOnly` and a ticket's `Red: skip` metadata are two independent policies that can disagree.** This ticket (P15.10) declares `Type: docs`, `Red: skip`, and touches only `.plist`/`.yml`/`.astro`/`.md` files — but the orchestrator's mechanical doc-only detector (`isLocalBranchDocOnly`) only recognizes `.md` and `.json` extensions. So `post-red` correctly auto-skipped (it reads `redPolicy` from ticket metadata directly), but `post-verify` and `subagent-review` did **not** auto-skip the way a `.md`-only ticket would have — this ticket ran the full subagent-review gate like a code ticket despite being declared doc-only in its own metadata. Worth knowing for future doc/version-bump tickets: don't assume `Red: skip` implies the review gates skip too.

**Cap eviction's priority order is legible enough that it needed no dedicated documentation beyond the enum comparison.** Grounding the eviction order directly against `ActivityState.swift`'s existing states (idle/standby → errored → waiting_for_input → active-never-evicted) meant there was no separate "priority score" concept to invent, test, or explain — the states already had an implicit urgency order from prior phases and P15.07 just formalized it as a comparator.

## What we'd do differently

**Re-run `subagent-review patched <sha>` after a post-recording fix, not just `reconcile-subagent-review`.** The reconciliation gate did its job — it caught the ledger/git divergence and hard-blocked until an audit row was appended — but the fix was to append a second "patched" row to the reconciliation trail rather than update the ticket's canonical `subagentReviewOutcome` field. `status` and any future automated read of `state.json` should show `patched`, not `clean`, for P15.05/06/08. This is a workflow discipline gap for future tickets, not a code change to `.son-of-anton/` (which is a read-only subtree here) — flag it upstream if it recurs.

**Land the `sessionCap` clamp with the Settings UI ticket instead of deferring a third time.** P15.09 was the natural point to add `max(0, ...)` at the write boundary since it's the first ticket that makes negative values reachable via any UI. Deferring again because "the dropdown doesn't offer negative values" ignores the hand-edited-file case the earlier advisory notes were explicitly about.

## Net assessment

Phase 15 delivered the full per-session-pet product contract — opt-in enable, cap, rename, prune, priority eviction, conflict signal, and Settings UI — without a single stop-condition trip and with the byte-identical-collapse gate holding through every downstream ticket. The subagent review gate earned its keep three times over with real, user-visible bugs caught before publication, even though the delivery state's own bookkeeping undersells that fact. The two open gaps (Minimalist rename/tooltip parity, negative-cap normalization) are both scoped, acknowledged, and small — neither blocks closeout.

## Follow-up

- **Session-linked SoA gate/ticket attribution across codogotchi + upstream `cesarnml/son-of-anton`.** Named as an explicit deferral in the Phase 15 plan and carried forward from Phase 14's "Upstream SoA attribution" follow-up (per-session SoA gate/animation attribution still resolves per-platform this phase). Blocked on `cesarnml/son-of-anton` emitting runtime platform + `session_id` attribution with gate signals — track as a cross-repo dependency, not a codogotchi-only ticket.
- **Minimalist-mode rename/tooltip parity:** extend `MinimalistPanelManaging` to consume `SessionLabelStore` and the last-prompt tooltip the same way `FloatingPetPanelManaging` does, closing the exit-condition gap noted above.
- **`sessionCap` negative-value clamp:** add the `max(0, ...)` guard at the `CustomizationTabViewModel.setSessionCap` write boundary (or the allocator read site) so a hand-edited `customization.json` can't produce an unbounded-but-not-Unlimited state.
- **`subagent-review` ledger accuracy:** when a post-recording patch lands and `reconcile-subagent-review` appends a "patched" audit row, consider whether the ticket's canonical `subagentReviewOutcome` should be corrected to match rather than left at its original (now stale) value — a process note for whoever next touches the upstream `son-of-anton` orchestrator.

---

_Created: 2026-07-02. PRs #150–#158 merged into the stack, P15.10 pending. Awaiting developer closeout approval._
