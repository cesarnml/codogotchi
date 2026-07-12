# Phase 18 — Pool Pipeline Split (Derive / Diff / Apply)

> Restructure `FloatingPetWindowPool.update()` into a pure `derive` (policy), a mechanical `diff`, and an effect-only `apply` via parallel build + shadow-compare, deleting the old imperative pipeline before phase exit.

## Epic

Product plan: `docs/product/plans/phase-18-pool-derive-diff-apply.md` (Track 4 closer; unblocks Track 2).

## Product contract

Zero intentional user-visible change (behavior freeze). What changes for the developer:

- "Which pets should exist" is answerable by calling a pure function with a tick input and a `PoolMemory` value — no stub controllers, no spawned windows.
- Every Phase 15 QC gap class (mode-transition teardown, hide vs. cap incumbency, grandfather admission, eviction frame-inheritance) is a named table-driven test row against `derive`.
- `update()` is a composition of `derive` → `diff` → `apply`; the old ~10-step imperative pipeline no longer exists in the codebase.

## Grill-Me decisions locked

1. **Derive shape → pure fold (Moore machine).** `derive(input, memory) → (DesiredWindows, memory′)` over an `Equatable` `PoolMemory` value type holding all cross-tick state (TTL clocks, first/last-seen, elections, slot occupants, pruned origins, evicted-frame FIFO, hidden keys, spawned modes, session numbering, prompt timers). Rationale: the Phase 15 bug classes live in state *transitions*; only a fold makes them table rows, and shadow-compare can diff both outputs.
2. **Memory scope → all-in, user actions as immediate pure transitions.** The session-number allocator and prompt timers convert to value types inside `PoolMemory`. Out-of-band actions (Hide/Show, Prune, Hide All Others, Force-Idle timer reset) become pure transition functions the shell applies to its stored memory immediately, paired with the immediate window effect — no event queue, no 1-tick lag. Rationale: allocation timing and observe-before-guards ordering are policy; directives would move that policy into `apply`, violating the plan's fixed constraint.
3. **Output spec → fat `DesiredWindows` with a title-resolution effect seam.** `DesiredWindow` carries every push payload as data (renderer kind, petId, session number, label, tooltip, activity state, prompt-timer status, attention, gate badge, platform chip, hudEnabled, conflict bubble, inherited-frame directive) plus pool-level outputs (`blockedOrigins`, `pendingSessionKeys`, `ttlDismissedWindowKeys`, hidden-keys-to-persist, monochrome change, idle-escalation config). Title resolution is impure (disk cache + subprocess + write-through), so `derive` emits `titleResolutionRequests` and `apply` resolves + writes through; results land next tick. **Accepted documented divergence:** a freshly-resolved title first appears ~1 tick (~1 s) later than today — a standing shadow-compare exemption.
4. **Shadow-compare → full fidelity, log-only in dogfood.** Decision sets (membership, spawned modes, blocked/pending/TTL-dismissed sets, session numbers, hidden keys) plus push payloads captured via a recording `FloatingPetWindowControlling` proxy, diffed field-by-field against `DesiredWindows`. Asserts in tests/debug; in the dogfood build divergences log to NSLog + an on-disk divergence log with a replayable tick-input fingerprint — never fatal. Frame-inheritance compared structurally (which keys inherit, in what order), never CGRect values.
5. **Granularity → 7 tickets, derive built as three unwired pure slices** (skeleton / selection / pushes), then mechanics, shadow, cutover, deletion+closeout. The plan's strangler rejection is about live-pipeline peeling; unwired pure code can grow across tickets without interleaving risk, keeping PRs reviewable.
6. **Soak gates → symmetric rare-branch checklists, no calendar minimums.** Cutover (P18.05 → P18.06) requires zero unexplained divergences under shadow **and** a scripted checklist exercised while shadowing: session cap overflow + eviction, grandfather admission (session-pets toggled both directions), hide-while-capped, manual Prune, own↔minimalist↔combined transitions, all three window shapes (Own, Minimalist, Combined). Deletion (P18.06 → P18.07) requires the same checklist repeated under the reversed shadow. This front-loads the Track 2 execution gate.

**Stated choices (approved with the breakdown):**

- New pure code lives in `apps/menubar/Sources/Pool/Derive/`.
- Purity gate: a CI-run check asserting no AppKit import anywhere under `Pool/Derive/` (exit condition 2's grep, automated).
- Cutover rollback: launch-time env var `CODOGOTCHI_POOL_ENGINE=legacy`; deleted with P18.07.
- `FloatingPetWindowPool` keeps its public surface throughout — `MenubarApp` wiring untouched.

## Ticket Order

1. `P18.01 Derive skeleton — PoolMemory, DesiredWindows, tick core`
2. `P18.02 Derive selection — cap/eviction, grandfather, frame directives, user-action transitions`
3. `P18.03 Derive pushes — combined folding and the fat push spec`
4. `P18.04 Diff, apply, recording proxy, and comparator`
5. `P18.05 Shadow tick — old drives, new shadows`
6. `P18.06 Cutover and role reversal`
7. `P18.07 Old-pipeline deletion and closeout`

## Ticket Files

- `ticket-01-derive-skeleton.md`
- `ticket-02-derive-selection.md`
- `ticket-03-derive-pushes.md`
- `ticket-04-diff-apply-comparator.md`
- `ticket-05-shadow-tick.md`
- `ticket-06-cutover.md`
- `ticket-07-deletion-closeout.md`

## Exit Condition

All six product-plan exit conditions demonstrably true on `v3_preview`:

1. The pool's update path is `derive` → `diff` → `apply`; the old imperative pipeline is deleted.
2. `derive` is pure with no AppKit imports (automated purity gate), consuming `SessionLifecycle` and `WindowKey`.
3. `DesiredWindows` + diff directives require zero additional policy decisions in `apply`, reviewed against every step of the former `update()` (the P18.03 step-mapping artifact).
4. Named table-driven tests cover all four Phase 15 QC gap classes; full existing suite green; `bun run verify` and `bun run ci:quiet` pass.
5. Pre-cutover shadow window and post-cutover reversed-shadow soak completed with every divergence explained and resolved via the divergence policy.
6. A local dogfood DMG is packaged, installed, and running as the daily driver.

## CI Baseline

> Baseline recorded: pending — run `bun run ci:quiet` on `v3_preview` before P18.01 starts and record the result here.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- **Divergence policy (binding):** when shadow-compare reveals the *old* pipeline is wrong, fix the old pipeline first, in a separate commit with a review-gap ledger entry, then require the new engine to match. No bug-for-bug replication in `derive`.
- **Behavior freeze:** the only permitted behavior deltas are divergence-policy bug fixes (with ledger entries) and the documented title-seam ~1-tick delay.

## Explicit Deferrals

- v4 hook-stamped `prompt_started_at` architecture (schema bump + hook binary + five installers).
- Any change to reader/writer disk contracts, clock defaults, or eviction/cap policy semantics.
- Full property-based/generative testing of `derive` — the named gap-class tables are the gate; randomized testing is a welcome stretch, not a gate.
- Performance work.
- Public release / notarization / Sparkle — Track 2's workstream; this phase's artifact is a local dogfood DMG only.

## Stop Conditions

- **P18.05 → P18.06 gate:** do not start cutover until the pre-cutover rare-branch checklist has been exercised under shadow with zero unexplained divergences. Developer confirms.
- **P18.06 → P18.07 gate:** do not start deletion until the same checklist has been repeated under the reversed shadow with zero unexplained divergences. Developer confirms.
- Any shadow divergence where it is genuinely unclear whether the old or new pipeline is correct — surface to the developer instead of picking a side.
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: this phase closes the Track 4 program and is the only phase that validates the derive/diff/apply bet itself; the retrospective is the program's closing verdict and is mechanically required by the Track 2 execution gate.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-18-pool-derive-diff-apply-retrospective.md`
