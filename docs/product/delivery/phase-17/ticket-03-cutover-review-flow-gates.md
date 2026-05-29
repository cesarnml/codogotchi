# P17.03 Cut over review-flow gates with emit-then-action

Size: 3 points
Type: feat
Scope: codogotchi-gate
Red: required

## Outcome

- `deliver write-subagent-adversarial-review` writes `adversarial_review` to `gate.json` before directing the adversarial-prompt write.
- `deliver open-pr` writes `open_pr` before `gh pr create` runs.
- `deliver poll-review` writes `poll_review` before polling begins.
- `deliver record-review` writes `record_review` before recording the outcome.
- All four emits go through the P17.01 writer to `$CODOGOTCHI_HOME/gate.json` with correct `plan_key`/`ticket_id`, and replace the legacy `events.ndjson` `pr_review_window_opened` emission on the open-pr path.
- `review_clean` and `subagent_invoked` are untouched in this ticket (P17.04).

## Red

- Add `tools/delivery/test/p17-03.test.ts` against a tmp `CODOGOTCHI_HOME`:
  - `write-subagent-adversarial-review` → `gate.json` is `adversarial_review`;
  - `open-pr` → `open_pr`;
  - `poll-review` → `poll_review`;
  - `record-review` → `record_review` (resident state before any clean-outcome handling);
  - each object carries the correct `plan_key`/`ticket_id`;
  - the open-pr path no longer appends `pr_review_window_opened` to `events.ndjson`.
- Run the suite, confirm failures.
- Commit `[red]`: `test(codogotchi-gate): review-flow gates emit-then-action [red]`.

## Green

- Move/replace each emit to the **top** of its command handler (before the heavy action) using the new writer.
- `adversarial_review` anchors on `write-subagent-adversarial-review` (not subagent runner start, not `subagent-review`).
- Replace the existing `emitSoaEventForOpenPr` `pr_review_window_opened` emission with the `open_pr` gate via the new writer; the `poll_review` gate now owns the AI-review-window beat.
- Smallest change to pass; do not touch `review_clean`/`subagent_invoked` or delete the old writer yet.

## Refactor

- Reuse the centralized gate-name constants from P17.02.
- Only touch the four review-flow handlers and their emit helpers.

## Review Focus

- Emit-then-action: each gate is written before its command's primary side effect (PR creation, polling, recording) — verify by call placement.
- `adversarial_review` timing is the write-prompt direction point, matching the codogotchi contract intent (intent visible before work).
- The split of the old single `pr_review_window_opened` into distinct `open_pr` (open-pr) and `poll_review` (poll-review) gates — no gate is dropped or double-emitted.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Export named 'emitRecordReviewGate' not found in module '../cli-runner.ts'` — all test groups failed at module resolution.
Why this path: Four symmetric exported functions (`emit*Gate`) follow the same pattern as P17.02 helpers; each handler resolves the target ticket from existing state and emits before its action. `emitSoaEventForOpenPr` becomes a no-op stub parallel to `emitSoaEventsForTransitions`.
Alternative considered: Inlining `writeGateEvent` directly in each handler — rejected because exported functions are testable in isolation and consistent with P17.02 pattern.
Deferred: `review_clean` and `subagent_invoked` emissions remain on the old `soa-event-feed.ts` writer; retired in P17.04.
Contract note: `appendSoaEvent` and `buildSoaEventLine` imports removed from `cli-runner.ts` since all their callers are now no-op stubs; no other files were affected.
