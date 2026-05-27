# P15.02 Emit ticket_started + ticket_completed

Size: 2 points
Type: feat
Scope: delivery
Red: required

## Outcome

- Running `deliver start <ticket>` in a consumer repo with `codogotchi.enabled` appends a `ticket_started` line to `.soa/events.ndjson` with `plan_key` and `ticket_id` matching the started ticket.
- Running `deliver advance` when a ticket transitions to `in_progress` (from any other state) appends a `ticket_started` line.
- Running `deliver advance` when a ticket transitions to `done` (from any other state) appends a `ticket_completed` line.
- An `advance` call that transitions both a previous ticket to `done` and a next ticket to `in_progress` appends both lines, in order: `ticket_completed` first, then `ticket_started`.
- Setting `codogotchi.enabled: false` suppresses both events.
- All emits are best-effort: a write failure does not abort the command or surface as an error to the caller.

## Red

- Add a Red test in `tools/delivery/test/p15-02.test.ts` that:
  - Sets up a fake delivery state in a tmp dir with one ticket pending.
  - Invokes the `start` command path with `codogotchi.enabled` and asserts the tmp `.soa/events.ndjson` contains exactly one `ticket_started` line with the correct `plan_key` and `ticket_id`.
  - Invokes an `advance` transition `in_progress → done` and asserts a `ticket_completed` line is appended (file now has two lines).
  - Invokes an `advance` that transitions ticket A → `done` while moving ticket B → `in_progress`, asserts both lines land in order: `ticket_completed` (A), then `ticket_started` (B).
  - With `codogotchi.enabled: false`, repeats the start + advance sequence and asserts the events file does not exist.
- Commit message: `test(P15.02): emit ticket_started and ticket_completed [red]`.

## Green

- In `cli-runner.ts`, after the `start` command's state transition succeeds, call `appendSoaEvent(process.cwd(), buildSoaEventLine('ticket_started', { plan_key, ticket_id }))` with values sourced from `state.planKey` and the started ticket id. Use the resolved config to gate.
- In `cli-runner.ts`, after each `advance` transition, derive the diff between `previousState` and `nextState` (the same diff `eventsForAdvanceCommand` already computes) and emit one event per transition: `ticket_completed` for `→ done`, `ticket_started` for `→ in_progress`. Emit in the same order `eventsForAdvanceCommand` returns: `ticket_completed` first, then `ticket_started`.
- Wrap each emit in the writer's own try/catch (already handled inside `appendSoaEvent`); no additional caller-side error handling needed.

## Refactor

- Consider extracting a small helper `emitSoaEventsForTransitions(previousState, nextState, config, projectRoot)` if the diff logic repeats between `advance` and `start` — only if there is genuine duplication, not preemptive.
- Do not refactor `eventsForAdvanceCommand` itself — its Telegram-notification responsibilities are orthogonal and out of scope.

## Review Focus

- Both events use `plan_key` from `state.planKey` and `ticket_id` from the transitioning ticket — not from CLI args.
- The `advance` emit fires from the orchestrator-level state diff, not from individual ticket-update calls — ensures the events match the Telegram notification semantics.
- Order matters when both transitions happen in one `advance`: `ticket_completed` before `ticket_started`.
- The gate check sits inside `appendSoaEvent`; the call site does not branch on `codogotchi.enabled`.
- No `.soa/` directory is created when the gate is disabled.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Import of `emitSoaEventsForTransitions` from `cli-runner.ts` failed — function did not exist yet.
Why this path: Extracted `emitSoaEventsForTransitions(previousState, nextState, config, projectRoot)` as a shared helper covering both `start` and `advance` paths. Both reduce to a state diff: find tickets whose status changed to `done` or `in_progress` and emit the corresponding event. Genuine duplication — the diff logic is identical for both callers.
Alternative considered: Wiring separate `appendSoaEvent` calls inline in `start` and `advance` without extracting a helper. Rejected because the `advance` case already has the diff logic in `eventsForAdvanceCommand`; extracting to a named helper keeps the contract explicit and testable.
Deferred: No `.soa/` directory creation path for disabled gate (handled entirely inside `appendSoaEvent` already). No event emission for `triage-ticket` or `triage-standalone` paths (scoped to `start` and `advance` only as specified).
