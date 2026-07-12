You are conducting an adversarial review of a code change.
You may add extra attack surfaces when your independent repo read finds a plausible
ticket-relevant failure path.
Findings outside the three finding-discipline clauses belong in **Advisory Observations** —
anything off-scope but real is welcome there.
Your job is not a general code review — it is a targeted attack on the behavior this ticket is supposed to
protect. Start from the invariants and attack surfaces below, then independently inspect
the diff and directly related implementation code for missing ticket-relevant risks. You
are looking for paths where the ticket's intended behavior breaks, not for general
improvements.

### Ticket scope

P17.02 wires gate-event emission to `start`, `advance`, and `post-red` handlers via new `writeGateEvent` calls (using `GATE_NAMES` constants from `codogotchi-gate.ts`):

- `deliver start <ticket>` writes `ticket_started` at handler entry, then writes `red_tdd` (Red: required) or `green_tdd` (Red: skip) at exit.
- `deliver advance` writes `ticket_completed` on done-transition, then `ticket_started` on next-ticket in-progress transition (cook mode: last-write-wins = `ticket_started` as resident gate).
- `deliver post-red` writes `green_tdd`.
- `emitSoaEventsForTransitions` is retired to a no-op stub (NDJSON `ticket_started`/`ticket_completed` emission removed).
- Review-flow gates (`adversarial_review`, `open_pr`, etc.) are not touched — they remain on the old writer.

### Files touched

Implementation:
tools/delivery/cli-runner.ts (start/advance/post-red handlers + new exported gate functions + emitSoaEventsForTransitions stub)
tools/delivery/codogotchi-gate.ts (GATE_NAMES constant added)

Tests:
tools/delivery/test/p17-02.test.ts (new tests for emitGateForTransitions, emitStartExitGate, emitPostRedGate)
tools/delivery/test/p15-02.test.ts (updated: retired NDJSON behavior reflected)
tools/delivery/test/fix-worktree-event-routing.test.ts (updated: retired NDJSON worktree-routing tests)

### Invariants to hold

1. `deliver start` must emit `ticket_started` before `startTicket` executes (emit-then-action), and must emit `red_tdd` (redPolicy=required) or `green_tdd` (redPolicy=skip) after `startTicket` completes.
2. `deliver advance` must write `ticket_completed` for the done-transitioning ticket and `ticket_started` for the newly-in-progress ticket; in cook mode these are sequential writes so `ticket_started` is the resident gate.json value.
3. `deliver post-red` must emit `green_tdd` after `recordPostRed` completes.

### Attack surfaces to probe

1. `startTargetId` resolution in the `start` handler: the logic uses `stateForStart.tickets.find(t => t.status === 'in_progress') ?? stateForStart.tickets.find(t => t.status === 'pending')`. Can a resume scenario (ticket already in_progress) cause `ticket_started` to be emitted for the wrong ticket?
2. `emitStartExitGate(startedTicket, ...)` — the `startedTicket` is resolved by searching `nextState.tickets` for the `startTargetId`. If `startTicket` mutates the ticket id or `startTargetId` was undefined (no pending ticket found), `startedTicket` may be `undefined`, silently skipping the exit gate.
3. `emitGateForTransitions` iteration order: the function iterates `previousState.tickets` and emits `ticket_completed` before `ticket_started`. Probe whether an order inversion (a `tickets` array where the pending ticket comes before the in-progress ticket) could cause the wrong gate to be the final resident.
4. `post-red` target resolution: the fallback `nextState.tickets.find(t => t.status === 'red_complete')` could find any already-complete ticket, not necessarily the one that just transitioned. Probe whether an already-complete ticket from a prior resume causes `green_tdd` to be emitted with the wrong `ticketId`.
5. `emitSoaEventsForTransitions` stub: the function is now a no-op. Its parameters are unused (prefixed with `_`). Confirm callers that previously relied on it for NDJSON emit no longer get those events — and confirm the retired behavior is intentional (not a silent regression).
6. `GATE_NAMES` constants in `codogotchi-gate.ts`: confirm they match the codogotchi schema-v4 ActivityState string values referenced in the Phase 17 plan.

#### Diff-derived attack surfaces

1. **Output stability across schema-version drift** — `GATE_NAMES` introduces new gate strings (`ticket_started`, `ticket_completed`, `red_tdd`, `green_tdd`, `adversarial_review`, `open_pr`, `poll_review`, `record_review`, `review_clean`). Probe whether any existing test fixture or prior NDJSON event line uses a different string for the same concept.
2. **CLI flag/arg symmetry** — No new CLI flags. `[N/A — no CLI changes in this diff]`
3. **Error-class breadth in `catch` blocks** — `writeGateEvent` calls are `await`-ed without their own catch in the new handler additions. Probe whether an unexpected rejection from `writeGateEvent` (which should not throw — it wraps in try/catch internally) could surface to the handler level.
4. **Defensive layering at module boundaries** — `emitStartExitGate` and `emitPostRedGate` accept a `TicketState` object from caller state. Probe whether a ticket with `redPolicy: undefined` (violating the type but possible if state migration is incomplete) would produce an incorrect gate name.
5. **Cross-file atomicity windows** — `start` handler: `writeGateEvent(ticket_started)` fires, then `startTicket` runs, then `emitStartExitGate` fires. If `startTicket` throws between these writes, `gate.json` reflects `ticket_started` but the ticket is not actually in_progress and the exit gate is never written. Probe whether this partial state is harmful.
6. **Test-contract strength** — The p17-02 tests verify the correct gate name in `gate.json` for each scenario. Probe whether they also verify `plan_key` and `ticket_id` fields (as specified in the invariants), and whether the cook-mode ordering test actually proves last-write-wins.
7. **Doc-vs-code drift in the ticket Rationale** — The Rationale says "Tests verify the gate name is correct; ordering is a code-structure guarantee." Verify the diff implements the ordering the Rationale claims (emit then action) and that the ticket Outcome description matches the implementation.

### Diff context

Key additions to `cli-runner.ts`:

1. Import `GATE_NAMES`, `writeGateEvent` from `./codogotchi-gate`.
2. In `start` case: resolve `startTargetId` from state before calling `startTicket`, emit `ticket_started` via `writeGateEvent`, call `startTicket`, find `startedTicket` in `nextState`, emit via `emitStartExitGate`.
3. In `post-red` case: after `recordPostRed`, find the ticket that just transitioned to `red_complete` and call `emitPostRedGate`.
4. In `advance` case: replace `emitSoaEventsForTransitions` call with `emitGateForTransitions`.
5. New exports: `emitGateForTransitions`, `emitStartExitGate`, `emitPostRedGate`.
6. `emitSoaEventsForTransitions` becomes a no-op stub with `_`-prefixed parameters.

Key addition to `codogotchi-gate.ts`:

- `GATE_NAMES` const object with 9 gate name strings.

---

### Your directives

**Scope:** You conduct an adversarial review of the implementation diff and directly
related code paths named in the attack surfaces. Do not expand scope beyond what the
ticket outcome describes.

**Advisory-only — no file writes:** You must not create, modify, or delete any file in
the repository. Your entire deliverable is findings prose in the required output format
below. The primary execution agent owns all patches.

**Read boundary for delivery docs:** Do not write files under `docs/product/delivery/**`
(or anywhere else). You **must** still read the ticket Rationale and any referenced
contract docs as part of probing the "Doc-vs-code drift in the ticket Rationale"
diff-derived surface above.

**Coverage mandate:** For each attack surface listed above, you must either probe it and
report what you found, or explain in one sentence why it does not apply. A clean result
on a surface you probed is a valid and valuable outcome.

**Finding discipline:** Report a finding when one of the following holds:

1. The code breaks a stated invariant.
2. The code introduces a correctness gap you can demonstrate.
3. **Spec-permits-real-bug:** the ticket's stated contract literally permits the behavior, but that behavior is nevertheless unsafe in production. Name which spec clause permitted the unsafe behavior.

**No fabrication pressure:** If all invariants hold and all attack surfaces are sound, your correct output is a clean report.

---

### Required output format

**Invariant results**
For each invariant: `[held | broken | untested]` — one line explaining what you tried.

**Surface results**
For each attack surface: `[probed | N/A — <reason> | blocked — missing-input]`
If probed: what you tried and what you found (one to three sentences).

**Actionable findings**
File/path, what is wrong, which invariant or finding-discipline clause applies, and a concrete fix. If none: "None."

**Advisory Observations**
One bullet or paragraph per observation. If none: "None."

**Runner termination**
`runnerStatus`: one of `completed | rate_limit | sandbox_denied | runner_unavailable`.
`terminatedReason`: one short sentence.
