You are conducting an adversarial review of a code change.
You may add extra attack surfaces when your independent repo read finds a plausible
ticket-relevant failure path.
Findings outside the three finding-discipline clauses belong in **Advisory Observations** —
anything off-scope but real is welcome there.
Your job is not a general code review — it is a targeted attack on the behavior this ticket is supposed to
protect. Start from the invariants and attack surfaces below, then independently inspect
the diff and directly related implementation code for missing ticket-relevant risks.

### Ticket scope

P17.03 cuts over four review-flow handlers to emit to `gate.json` before their primary action:

- `write-subagent-adversarial-review` → `adversarial_review` gate before prompt write
- `open-pr` → `open_pr` gate before `openPullRequest`, removing the old `emitSoaEventForOpenPr` NDJSON call
- `poll-review` → `poll_review` gate before polling/skip logic
- `record-review` → `record_review` gate before `recordReview`
- `emitSoaEventForOpenPr` retired to no-op stub; `appendSoaEvent`/`buildSoaEventLine` imports removed from `cli-runner.ts`
- `review_clean` and `subagent_invoked` are untouched (P17.04)

### Files touched

Implementation:
tools/delivery/cli-runner.ts (4 handler wires + emitSoaEventForOpenPr stub + 4 new exports + import cleanup)

Tests:
tools/delivery/test/p17-03.test.ts (new tests for 4 gate functions + retired NDJSON assertion)
tools/delivery/test/p15-03.test.ts (updated: retired NDJSON behavior reflected)

### Invariants to hold

1. Each of the four gates (`adversarial_review`, `open_pr`, `poll_review`, `record_review`) must be emitted to `gate.json` **before** the handler's primary action executes.
2. The `open-pr` handler must no longer append `pr_review_window_opened` to `events.ndjson` (NDJSON emission retired; gate.json replaces it).
3. `review_clean` and `subagent_invoked` emission paths must remain unchanged (not touched in this ticket).

### Attack surfaces to probe

1. `emitAdversarialReviewGate` placement in `write-subagent-adversarial-review`: the emit fires after validation guards (`writeTarget` resolve, `writePolicy` check, `writeIsDocOnly` check). If a guard throws, the gate is never emitted. Probe whether the "emit-then-action" spec requires emission to precede ALL errors, or only the primary side-effect action.
2. `openPrTarget` resolution in `open-pr`: uses `state.tickets.find(t => t.status === 'subagent_review_complete')` as fallback. Probe whether a ticket at any other status (e.g., `verified` after `--ack-reconciliation`) would prevent `openPrTarget` from being found, silently skipping the `open_pr` gate.
3. `emitPollReviewGate` timing in `poll-review`: the emit fires before the `shouldAutoRecordReviewSkippedForPollReview` check. For disabled PRs (our config), the skip path triggers immediately after the gate. Verify the gate is not emitted twice (once for skip, once for the normal poll path).
4. `emitRecordReviewGate` validation order in `record-review`: the arg-validation `throw` runs before `recordTarget` lookup and gate emit. Probe whether this is correct for the "emit-then-action" intent (gate should emit before action, not before argument validation).
5. `emitSoaEventForOpenPr` no-op stub: confirm the function no longer references `appendSoaEvent`, `buildSoaEventLine`, or `eventsForOpenPrCommand`. Probe whether any other caller of this function in `cli-runner.ts` or tests expects NDJSON output.
6. `appendSoaEvent` / `buildSoaEventLine` removal from imports: confirm these are not referenced elsewhere in `cli-runner.ts` after the cleanup.

#### Diff-derived attack surfaces

1. **Output stability across schema-version drift** — `emitSoaEventForOpenPr` previously emitted `pr_review_window_opened` to NDJSON. Probe whether any consumer of `events.ndjson` relies on this event name (codogotchi renderer, tests, scripts).
2. **CLI flag/arg symmetry** — No new flags. `[N/A]`
3. **Error-class breadth in catch blocks** — The four new `emit*Gate` functions each delegate to `writeGateEvent` which wraps all errors in `try/catch`. Probe whether any handler-level error path could prevent the gate from being attempted (e.g., the guard throw above the emit call).
4. **Defensive layering at module boundaries** — The `openPrTarget` lookup uses `state.tickets.find(...)` from the pre-action state. If `runAckReconciliation` mutates state (it operates on `state` not `nextState`), would `openPrTarget` resolve correctly?
5. **Cross-file atomicity windows** — `open-pr`: gate emits, then `openPullRequest` runs. If `openPullRequest` fails (e.g., GitHub API error), `gate.json` shows `open_pr` but no PR was created. Probe whether this partial state is acceptable.
6. **Test-contract strength** — The p17-03 tests verify gate name, plan_key, and ticket_id for each function. Probe whether there's a test confirming `emitSoaEventForOpenPr` does NOT create `.soa/events.ndjson` (the retired NDJSON assertion from Invariant 2).
7. **Doc-vs-code drift in ticket Rationale** — The Rationale says "emit-then-action" for all four handlers. Verify each emit is placed before its action in the diff.

### Diff context

1. `write-subagent-adversarial-review` case: `emitAdversarialReviewGate` added before `resolveAdversarialPromptContent`.
2. `open-pr` case: `openPrTarget` resolved from state, `emitOpenPrGate` called before `openPullRequest`; `emitSoaEventForOpenPr` call removed.
3. `poll-review` case: `emitPollReviewGate` called after `pollTarget` is found, before the skip check.
4. `record-review` case: `recordTarget` found from state, `emitRecordReviewGate` called before `recordReview`.
5. `emitSoaEventForOpenPr`: body replaced with `_`-prefixed params and no-op comment.
6. Import: `appendSoaEvent` and `buildSoaEventLine` removed from the `./soa-event-feed` import.
7. Four new exports: `emitAdversarialReviewGate`, `emitOpenPrGate`, `emitPollReviewGate`, `emitRecordReviewGate`.

---

### Your directives

**Scope:** Adversarial review of the implementation diff and directly related code paths. Do not expand beyond the ticket outcome.

**Advisory-only — no file writes:** Your deliverable is findings prose only.

**Coverage mandate:** Probe or explain N/A for every surface.

**Finding discipline:** Report when: (1) invariant broken, (2) correctness gap demonstrable, (3) spec-permits-real-bug. Style and hypotheticals go in Advisory Observations.

**No fabrication pressure:** A clean report is correct if all invariants hold.

---

### Required output format

**Invariant results**
For each invariant: `[held | broken | untested]` — one line.

**Surface results**
For each attack surface: `[probed | N/A — <reason> | blocked — missing-input]`
If probed: what you tried and what you found (one to three sentences).

**Actionable findings**
File/path, what is wrong, which clause, concrete fix. If none: "None."

**Advisory Observations**
One bullet or paragraph per observation. If none: "None."

**Runner termination**
`runnerStatus`: `completed | rate_limit | sandbox_denied | runner_unavailable`.
`terminatedReason`: one short sentence.
