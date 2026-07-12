# P15.03 Emit pr_review_window_opened

Size: 1 point
Type: feat
Scope: delivery
Red: required

## Outcome

- Running `deliver open-pr` in a consumer repo with `codogotchi.enabled` appends a `pr_review_window_opened` line to `.soa/events.ndjson` only when `buildReviewWindowReadyEvent` returns a non-undefined event (i.e., both `prUrl` and `prOpenedAt` are set and parse cleanly).
- The emit fires once per `open-pr` invocation that produces a real review window.
- The emit does NOT fire on the `pr_opened` event — only on `review_window_ready`. A PR that is opened but has no `prOpenedAt` produces no `pr_review_window_opened` line.
- The line carries `plan_key` from `state.planKey` and `ticket_id` from the ticket associated with the PR.
- Setting `codogotchi.enabled: false` suppresses the event.

## Red

- Add a Red test in `tools/delivery/test/p15-03.test.ts` that:
  - Sets up a fake delivery state with a ticket that has `prUrl` and `prOpenedAt` populated.
  - Invokes the `open-pr` command path and asserts a `pr_review_window_opened` line is appended.
  - Asserts the line has `name === 'pr_review_window_opened'`, `plan_key`, and `ticket_id`.
  - Sets up a second case with a ticket that has `prUrl` but missing `prOpenedAt` and asserts no `pr_review_window_opened` line is emitted (even if a `pr_opened` Telegram notification would fire).
  - With `codogotchi.enabled: false`, repeats and asserts no events file is created.
- Commit message: `test(P15.03): emit pr_review_window_opened [red]`.

## Green

- In `cli-runner.ts`, in the `open-pr` command handler, after `eventsForOpenPrCommand` returns its event list, inspect the list for the `review_window_ready` event specifically. If present, call `appendSoaEvent(process.cwd(), buildSoaEventLine('pr_review_window_opened', { plan_key, ticket_id }))`.
- Alternative implementation that may be cleaner: call `buildReviewWindowReadyEvent` directly with the current state + ticket, check for `undefined`, and emit on non-undefined return. Pick whichever path is the smallest change.

## Refactor

- If the `pr_opened` / `review_window_ready` event list inspection appears in multiple places, extract a helper. Otherwise leave inline — the call site is one place.

## Review Focus

- The emit fires only when the review window is real (both `prUrl` and `prOpenedAt` valid), not on `pr_opened` alone.
- The codogotchi event name is `pr_review_window_opened` even though the SoA notification kind is `review_window_ready` — verify the string is the codogotchi-side name.
- `plan_key` and `ticket_id` propagate correctly.
- Single emit per `open-pr` invocation — no duplicate lines on retries.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Import of `emitSoaEventForOpenPr` from `cli-runner.ts` failed — function did not exist yet.
Why this path: Extracted `emitSoaEventForOpenPr(state, config, projectRoot, ticketId?)` as a named exported helper that scans `eventsForOpenPrCommand(state, ticketId)` for a `review_window_ready` event. Using the existing `review_window_ready` event kind reuses the already-correct predicate (requires `prUrl` + `prOpenedAt`); the extracted helper is unit-testable without invoking the full CLI handler.
Alternative considered: Calling `buildReviewWindowReadyEvent` directly at the emit site rather than scanning the notification-event list. Both approaches resolve to the same condition; scanning the notification list was chosen because it is symmetric with the P15.04 pattern and keeps the emit adjacent to the handler's event array construction.
Deferred: Integration test dispatching the full `open-pr` CLI handler and asserting `.soa/events.ndjson` content (tests cover the exported helper only).
