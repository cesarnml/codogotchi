# P17.04 Cut over review_clean, retire subagent_invoked, delete soa-event-feed.ts

Size: 3 points
Type: feat
Scope: codogotchi-gate
Red: required

## Outcome

- A clean review outcome writes `review_clean` to `gate.json` across all three paths: `record-review`, `poll-review`, and `triage-ticket`.
- The `subagent_invoked` emit and its `emitSubagentInvoked` helper are removed entirely (no `gate.json` equivalent; not replaced).
- `tools/delivery/soa-event-feed.ts` is deleted; no `appendSoaEvent`, `buildSoaEventLine`, `emitSubagentInvoked`, or `maybeEmitReviewCleanRecorded` references remain anywhere.
- No delivery command writes to `.soa/events.ndjson` any longer; the only sidecar emission is `$CODOGOTCHI_HOME/gate.json`.
- All remaining gates (from P17.02/P17.03) still write correctly through the new writer.

## Red

- Add `tools/delivery/test/p17-04.test.ts` against a tmp `CODOGOTCHI_HOME`:
  - `record-review` clean → `gate.json` is `review_clean`;
  - `poll-review` resolving clean → `review_clean`;
  - `triage-ticket` reconciled clean → `review_clean`;
  - a non-clean outcome does not write `review_clean`.
- Add an assertion (or grep-style guard test) that no `.soa/events.ndjson` is created by any covered command.
- Run the suite, confirm failures.
- Commit `[red]`: `test(codogotchi-gate): review_clean across paths + no events.ndjson [red]`.

## Green

- Replace `maybeEmitReviewCleanRecorded` usage with a `review_clean` emit through the new writer on the clean branch of all three paths.
- Delete the `subagent_invoked` emit call site and `emitSubagentInvoked`.
- Delete `soa-event-feed.ts` and remove all imports of it from `cli-runner.ts`.
- Make the suite green; fix any now-dangling imports/types from the deletion.

## Refactor

- Remove any now-unused helpers, types, or test fixtures tied to the NDJSON writer.
- Confirm no `events.ndjson`, `.soa/`, or `appendSoaEvent` strings remain outside historical docs.

## Review Focus

- All three clean-outcome paths emit `review_clean` (a late clean via triage is semantically identical to a direct clean record — no dead spot).
- Complete removal: no orphaned imports, dead helpers, or lingering NDJSON writes after the delete.
- `subagent_invoked` removal does not break the subagent spawn flow itself (only the emit is removed).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Export named 'emitReviewCleanGate' not found in module '../cli-runner.ts'` — all test groups failed at module resolution.
Why this path: `emitReviewCleanGate(events, config, planKey)` mirrors `maybeEmitReviewCleanRecorded`'s event-detection pattern but writes to `gate.json` via `writeGateEvent`. This shared detection pattern means all three clean-outcome paths (poll-review, record-review, triage-ticket) get coverage from one function. `eventRoot` removed because all remaining emit calls now use CODOGOTCHI_HOME, not project-local paths.
Alternative considered: Keeping `soa-event-feed.ts` as a stub like `emitSoaEventsForTransitions` — rejected because no other caller remains; a dead module stub is confusing. Clean deletion is more honest.
Deferred: None — all gates and all retiring listed in the ticket outcome are complete.
Contract note: p15-01.test.ts, p15-04.test.ts, p15-05.test.ts deleted (they tested the retired NDJSON writer). Exports removed from orchestrator.ts barrel (AppendSoaEvent, buildSoaEventLine, maybeEmitReviewCleanRecorded, SoaEventLine).
