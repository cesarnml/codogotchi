# P21.05 Subagent-review outcome notification

Size: 2 points
Type: feat
Scope: notifications
Red: required

## Outcome

- `DeliveryNotificationEvent` (`tools/delivery/types.ts`) gains a `subagent_review_recorded` member carrying `planKey`, `ticketId`, `ticketTitle`, `branch`, the recorded outcome (including `completed_with_findings` from P21.02), and the actionable-findings count when available.
- `tools/delivery/notifications.ts` gains `buildSubagentReviewRecordedEvent` and `eventsForSubagentReviewCommand` in the style of their `review_recorded` siblings, plus a `buildNotificationPayload` case whose message text differs meaningfully: clean → low-urgency "passed, no actionable findings"; `completed_with_findings` → "found N actionable finding(s)"; `skipped` → states the termination reason.
- The `subagent-review` command handler (`tools/delivery/cli-runner.ts`) emits the event via `emitNotificationWarnings` after recording the outcome — best-effort, matching the existing one-liner pattern; a notifier failure never throws or blocks the command.
- `red_tdd`/`green_tdd` gates are **not** notified (out of scope per #87 — they belong to the animation layer).

## Red

- Write failing tests in `tools/delivery/test/`:
  - a recorded subagent-review outcome produces exactly one `subagent_review_recorded` event with the recorded outcome and count;
  - payload text for `clean` vs. `completed_with_findings` vs. `skipped` differs and includes the findings count for the findings case;
  - no event is produced for commands that did not record a subagent-review outcome;
  - a throwing notifier surfaces a warning without failing the command (reuse the existing best-effort test pattern).
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P21.05): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Copy the `review_recorded` end-to-end shape (event builder → eventsFor → payload case → handler emission) with the smallest change that passes.

## Refactor

- Only align naming with sibling builders; no opportunistic cleanup.

## Review Focus

- Emission point: after the ledger row is written, so the notification reflects what was actually recorded — never a pre-record guess.
- Fallback runs (P21.03): one notification per _recorded outcome_, not per attempt; a chain that fell back and succeeded notifies the final outcome only.
- Message honesty mirrors #83: the text must state what was found, never "passed" for a findings-bearing report.
- Intentionally deferred: Discord transport (#86); red/green gate notifications.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `SyntaxError: Export named 'eventsForSubagentReviewCommand' not found in module` when running `tools/delivery/test/p21-05.test.ts` against a worktree with the test file committed but `notifications.ts`/`types.ts` stashed out — confirmed via `git stash` of the two implementation files, matching the discipline established in P21.03/P21.04.
Why this path: copied the `review_recorded` end-to-end shape verbatim (event union member → `buildSubagentReviewRecordedEvent`/`eventsForSubagentReviewCommand` → `formatNotificationMessage` case → one `emitNotificationWarnings` call per recording site) rather than inventing new plumbing — the smallest change, and it keeps `subagent_review_recorded` consistent with how every other milestone event in this file already round-trips.
Alternative considered: a single shared `eventsForSubagentReviewCommand` call site placed after the `switch` on `dispatch.kind`/runner-outcome, rather than one call per branch (operator-recorder vs. programmatic-runner). Rejected — the two branches build `nextState` and the outcome value differently (`dispatch.outcome` vs. `outcome`/`stateOutcome`), and unifying them would have required extracting a new shared helper beyond what the ticket asked for.
Deferred: Discord transport (#86) and red/green gate notifications, both explicitly out of scope per the ticket text; `--subagent-model`/`--subagent-effort` (P21.04) have no bearing on this ticket's notification payload.
Contract note: none — `Type: feat`, `Scope: notifications`, `Red: required` all matched the actual change.
