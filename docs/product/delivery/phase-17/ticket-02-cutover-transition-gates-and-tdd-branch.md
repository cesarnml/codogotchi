# P17.02 Cut over transition gates + red_tdd/green_tdd start-exit branch

Size: 3 points
Type: feat
Scope: codogotchi-gate
Red: required

## Outcome

- `deliver start <ticket>` writes `ticket_started` to `gate.json` at handler entry, then — before returning — writes `red_tdd` if the ticket is `Red: required` or `green_tdd` if `Red: skip`.
- `deliver advance` writes `ticket_completed` on a ticket's transition to `done`, and `ticket_started` on the cook-mode auto-start transition of the next ticket to `in_progress`.
- `deliver post-red` writes `green_tdd`.
- All four/five emits go through the P17.01 `codogotchi-gate.ts` writer to `$CODOGOTCHI_HOME/gate.json` (not `events.ndjson`).
- Cook-mode `advance` emits `ticket_completed` then `ticket_started` in sequence (last write wins → `ticket_started` is the resident gate).
- The legacy `events.ndjson` `ticket_started`/`ticket_completed` emission in `emitSoaEventsForTransitions` no longer runs (replaced, not duplicated).

## Red

- Add `tools/delivery/test/p17-02.test.ts` against a tmp `CODOGOTCHI_HOME`:
  - `start` on a `Red: required` ticket → final `gate.json` is `red_tdd` (with `ticket_started` having been written first — assert resident state is `red_tdd`);
  - `start` on a `Red: skip` ticket → resident `gate.json` is `green_tdd`;
  - `post-red` → `green_tdd`;
  - `advance` to `done` (gated, no next ticket) → `gate.json` is `ticket_completed`;
  - cook-mode `advance` with a next pending ticket → resident `gate.json` is `ticket_started` for the next ticket;
  - each written object carries the correct `plan_key`/`ticket_id`.
- Run the suite, confirm failures.
- Commit `[red]`: `test(codogotchi-gate): transition gates + tdd start-exit branch [red]`.

## Green

- Rewire the `start` handler to emit `ticket_started` at entry and branch on the ticket's `Red:` metadata before returning to emit `red_tdd`/`green_tdd`.
- Rewire `emitSoaEventsForTransitions` (or its callers) to use the new writer for `ticket_started`/`ticket_completed`; add the `→ red_complete` transition emit of `green_tdd` for the `post-red` path.
- Determine `Red: required` vs `Red: skip` from the existing ticket/plan metadata already available in the handler (the same signal that drives `post-red` requirement).
- Smallest change to pass — leave review-flow gates (`adversarial_review`, `open_pr`, `poll_review`, `record_review`, `review_clean`) and `subagent_invoked` on the old writer for now.

## Refactor

- Centralize the gate-name strings so P17.03/P17.04 reuse them.
- Only touch `start`/`advance`/`post-red` paths and the transition emitter — no review-flow changes.

## Review Focus

- `ticket_started` truly precedes `red_tdd`/`green_tdd` within `start` (emit-then-action: entry vs pre-return), with the orientation work in between.
- `Red: skip` tickets never call `post-red`, so `green_tdd` for them must come from the `start` exit branch — confirm both paths emit `green_tdd` and there is no double-emit for `Red: required`.
- Cook-mode ordering: `ticket_completed` then `ticket_started`, last-write-wins.
- No remaining `events.ndjson` write for `ticket_started`/`ticket_completed` (no duplicate emission).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Export named 'emitGateForTransitions' not found in module '../cli-runner.ts'` — all 6 tests failed at module resolution.
Why this path: Three exported functions (`emitGateForTransitions`, `emitStartExitGate`, `emitPostRedGate`) added to `cli-runner.ts` so handlers and tests share the same well-typed gate-emit helpers. `emitSoaEventsForTransitions` becomes a no-op stub so existing call sites compile without change while the retired NDJSON behavior is cleanly removed.
Alternative considered: Deleting `emitSoaEventsForTransitions` immediately — rejected because that would require updating all call sites in this ticket; leaving the stub defers that cleanup to P17.04 as planned.
Deferred: Review-flow gates (`adversarial_review`, `open_pr`, `poll_review`, `record_review`, `review_clean`) remain on the old `soa-event-feed.ts` writer; those are cut over in P17.03/P17.04.
Contract note: `ticket_started` at `start` entry is emitted before `startTicket` executes, satisfying the "emit-then-action" requirement. Tests verify the gate name is correct; ordering is a code-structure guarantee reviewed here rather than a timing assertion.
