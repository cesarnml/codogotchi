You are conducting an adversarial review of a code change.
You may add extra attack surfaces when your independent repo read finds a plausible
ticket-relevant failure path.
Findings outside the three finding-discipline clauses belong in **Advisory Observations** —
anything off-scope but real is welcome there.
Your job is not a general code review — it is a targeted attack on the behavior this ticket is supposed to protect.

### Ticket scope

P17.04 is the final cleanup ticket:

- A new `emitReviewCleanGate(events, config, planKey)` function emits `review_clean` to `gate.json` when `events` contains a `review_recorded` event with `outcome === 'clean'`.
- Wired to all three clean-outcome paths: `poll-review`, `record-review`, `triage-ticket`.
- `emitSubagentInvoked` call site removed from the subagent spawn block.
- `soa-event-feed.ts` deleted entirely.
- All imports of NDJSON helpers removed from `cli-runner.ts` and `orchestrator.ts`.
- `eventRoot` variable removed (was only used for NDJSON emitters).
- Test files for retired NDJSON functionality deleted: `p15-01.test.ts`, `p15-04.test.ts`, `p15-05.test.ts`.

### Files touched

Implementation:
tools/delivery/cli-runner.ts (emitReviewCleanGate + wiring + import cleanup + eventRoot removal + emitSubagentInvoked removal)
tools/delivery/orchestrator.ts (removed soa-event-feed re-exports)
tools/delivery/soa-event-feed.ts (deleted)

Tests:
tools/delivery/test/p17-04.test.ts (new)
tools/delivery/test/p15-01.test.ts (deleted)
tools/delivery/test/p15-04.test.ts (deleted)
tools/delivery/test/p15-05.test.ts (deleted)

### Invariants to hold

1. `review_clean` is emitted to `gate.json` for all three clean-outcome paths (`record-review clean`, `poll-review resolves clean`, `triage-ticket reconciles clean`), and is NOT emitted when outcome is non-clean.
2. No `soa-event-feed` module exists in `tools/delivery/`; no live code imports from it.
3. The subagent spawn flow (runner invocation, artifact writing, ledger) is unaffected by the `emitSubagentInvoked` call removal — the emit was advisory-only and its removal must not break the runner.

### Attack surfaces to probe

1. `emitReviewCleanGate` event matching: the function finds the first event where `e.kind === 'review_recorded' && e.outcome === 'clean'`. Probe whether `eventsForPollReviewCommand`, `eventsForRecordReviewCommand`, `eventsForReconcileLateReviewCommand` actually emit a `review_recorded` event with `outcome === 'clean'` for their respective clean-outcome states.
2. `eventRoot` removal: the variable was also passed to `emitSoaEventForOpenPr` (now a no-op stub), `emitSoaEventsForTransitions` (now a no-op stub), and `maybeEmitReviewCleanRecorded` (replaced). Confirm no other active code in `cli-runner.ts` reads `eventRoot`.
3. Subagent spawn flow continuity: after removing `emitSubagentInvoked` (lines 995–1002), the `try` block runs `spawnSync` directly. Probe whether the removed `void emitSubagentInvoked(...)` and the subsequent `spawnSync` share any shared state (e.g., `worktreePath`, `bin`, `args`) that could cause a null/undefined dereference.
4. `orchestrator.ts` barrel: the removed exports (`appendSoaEvent`, `buildSoaEventLine`, `maybeEmitReviewCleanRecorded`, `SoaEventLine`) were part of the public barrel. Any external consumer (consumer repos, tests) that imported these symbols from `./orchestrator` would now break. Probe whether any live code imports these from the barrel.
5. Deleted test files: `p15-01.test.ts` tested `appendSoaEvent`/`buildSoaEventLine`, `p15-04.test.ts` tested `maybeEmitReviewCleanRecorded`, `p15-05.test.ts` tested `emitSubagentInvoked`. Confirm each deleted test file imported exclusively from `soa-event-feed` (not from `cli-runner` or other surviving modules).
6. `planKey` vs. `reviewEvent.planKey`: `emitReviewCleanGate` uses `planKey` parameter for `writeGateEvent` but uses `reviewEvent.ticketId` for `ticketId`. Probe whether the `planKey` passed by all three callers is always `state.planKey` and whether `reviewEvent.ticketId` is the correct ticket.

#### Diff-derived attack surfaces

1. **Output stability across schema-version drift** — The NDJSON `review_clean_recorded` event name is retired; `review_clean` now goes to gate.json. Probe whether any downstream consumer, script, or test references `review_clean_recorded` by name outside historical docs.
2. **CLI flag/arg symmetry** — No new flags. `[N/A]`
3. **Error-class breadth in catch blocks** — `emitReviewCleanGate` delegates to `writeGateEvent` which swallows all errors. No new catch blocks added. `[N/A — established best-effort pattern]`
4. **Defensive layering at module boundaries** — `eventRoot` removal: confirm the `findPrimaryWorktreePath` call that built it is also removed (otherwise unused call).
5. **Cross-file atomicity windows** — gate emits happen before review recording in P17.03; the clean gate in P17.04 happens after. Probe whether `review_clean` being emitted after recording (not before) violates the "emit-then-action" spec.
6. **Test-contract strength** — `p17-04.test.ts` tests `emitReviewCleanGate` directly. Probe whether the tests cover all three paths and whether the non-clean case (no gate written) is tested.
7. **Doc-vs-code drift in ticket Rationale** — The Rationale says `eventRoot` removed "because all remaining emit calls now use CODOGOTCHI_HOME, not project-local paths." Verify this is true — are there any surviving calls that use `eventRoot` or a project-local path?

### Diff context

Key changes:

1. `emitReviewCleanGate` added after `emitRecordReviewGate` in `cli-runner.ts`.
2. Four `maybeEmitReviewCleanRecorded` calls replaced with `emitReviewCleanGate(events, context.config, state.planKey)`.
3. `void emitSubagentInvoked(...)` block removed from subagent spawn try block.
4. Import `{ emitSubagentInvoked, maybeEmitReviewCleanRecorded }` from `./soa-event-feed` removed.
5. `const eventRoot = ...` line removed.
6. `orchestrator.ts` loses 5 re-exports.
7. `soa-event-feed.ts` deleted (49 lines).
8. Three test files deleted (testing exclusively deleted functionality).

---

### Your directives

**Scope:** Adversarial review of the implementation diff and directly related code paths.

**Advisory-only — no file writes:** Your deliverable is findings prose only.

**Coverage mandate:** Probe or explain N/A for every surface.

**Finding discipline:** (1) invariant broken, (2) correctness gap, (3) spec-permits-real-bug.

**No fabrication pressure:** Clean is valid.

---

### Required output format

**Invariant results**
For each invariant: `[held | broken | untested]` — one line.

**Surface results**
For each attack surface: `[probed | N/A — <reason> | blocked — missing-input]` + what you found.

**Actionable findings**
File/path, what is wrong, clause, fix. If none: "None."

**Advisory Observations**
One bullet per observation. If none: "None."

**Runner termination**
`runnerStatus`: completed | rate_limit | sandbox_denied | runner_unavailable.
`terminatedReason`: one sentence.
