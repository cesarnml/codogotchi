# P3.02 Hook v2 detection — requesting_input + errored

Size: 3 points
Type: feat
Scope: cli
Red: required

## Outcome

- `packages/cli/src/hook-binary.ts` classifies an incoming Claude Code / Codex `Stop` event whose payload indicates the agent is awaiting user input as `requesting_input`.
- The same hook classifies an incoming agent-response-failure event (rate limit, network error, or any stdin shape indicating an incomplete response cycle) as `errored`.
- SoA gate-event precedence is unchanged: a fresh SoA event still wins over the two new tool-stream classifications (they live at the heuristic tier alongside `pushing` / `running-tests` / `implementing` / `reviewing`).
- The hook writes `state.json` with `schema_version: 2` going forward (consumes `STATE_JSON_SCHEMA_VERSION` from `@codogotchi/contracts` — no hardcoded number in the hook).
- The `source_event` field continues to carry `origin`, `kind`, and `name` correctly for the two new state classifications. `kind` uses the existing `tool_use` or `session_end` enum value as appropriate; no new `kind` is introduced.
- Existing v1-classification behavior for all 13 prior states is unchanged.

## Red

- Write a test that a hook invocation receiving a `Stop`-shaped stdin payload with the user-input-awaited signal classifies as `requesting_input`.
- Write a test that a hook invocation receiving an agent-response-failure-shaped stdin payload classifies as `errored`.
- Write a test that a fresh SoA `ticket_started` event in the same hook step overrides the two new classifications (precedence preserved).
- Write a test that the hook writes `state.json` with `schema_version: 2`.
- Write a regression test asserting one prior v1 classification (e.g., `Edit` → `implementing`) still produces the expected state.
- Run `bun run test` against the cli package and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P3.02): hook v2 classifications [red]`.

## Green

- Extend the classify function in `hook-binary.ts` with two new branches: `requesting_input` (Stop event awaiting input) and `errored` (response failure).
- Decide the exact Stop-event shape and the exact failure-event shape during Green — record both in the ticket Rationale section so future hook revisions know what's covered.
- Reference `STATE_JSON_SCHEMA_VERSION` from `@codogotchi/contracts` rather than hardcoding `2`. Removes a future-bump foot-gun.
- Smallest change that makes the failing tests pass. Do not refactor the classify function's shape; do not introduce a new abstraction layer for "heuristic detectors."

## Refactor

- Only touch the classify function and its direct test fixtures. Do not opportunistically tidy the test runner setup, hook entrypoint plumbing, or sidecar IO code.
- If the two new branches share preprocessing (e.g., both inspect `hook_event_name`), extract the shared step into a single helper used by both — but only if the duplication is real, not theoretical.

## Review Focus

- The exact Stop-event payload shape that produces `requesting_input` is documented in the Rationale section (origin, kind, name, any payload key/value the classifier matches on).
- The set of failure modes that produce `errored` is documented in the Rationale section. Edge cases that were *not* covered (e.g., user Ctrl-C interrupt, tool-call timeout that the model would have recovered from) are explicitly listed as deferred.
- SoA precedence is unchanged — confirm the new branches sit below the SoA-event short-circuit in the classify function.
- `schema_version: 2` is sourced from the contracts package, not duplicated locally.
- The `source_event.origin` / `kind` enums are still respected — no new enum value snuck in.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `classifies Stop event as requesting_input` — exposed the missing `hook_event_name === "Stop"` branch in `classifyEvent`.
Why this path: A `Set`-based `FAILURE_STOP_REASONS` helper + two `if` blocks after the SoA gate is the smallest change that makes all six new tests pass without touching any other function.
Alternative considered: Detecting `requesting_input` broadly via `kind === "session_end"` (covering both `"stop"` and `"session_end"` raw names). Rejected — it would reclassify Codex `session_end` events that currently map to `idle` and break existing tests.
Deferred: `stop_reason: "stop_sequence"` / `"tool_use"` not classified as errored (ambiguous intent). User Ctrl-C produces no hook event — undetectable at this tier. Tool-call timeouts the model would have recovered from are also deferred.
Stop-event shape captured: `{ hook_event_name: "Stop" }` (uppercase as Claude Code sends; Codex lowercase `"stop"` also matches via `.toLowerCase()`). `rawHookOrigin` → `claude_code`; `rawHookKind` → `session_end`. Absence of `stop_reason` or `is_error` → `requesting_input`.
Failure-event shape captured: (1) `{ hook_event_name: "Stop", stop_reason: "max_tokens" }` — response truncated by token limit. (2) Any event with `{ is_error: true }` — explicit failure flag for rate-limit or network-error notifications from either agent runtime.
Contract note: No deviations. `Type: feat`, `Scope: cli`, `Red: required` all match as specified.
