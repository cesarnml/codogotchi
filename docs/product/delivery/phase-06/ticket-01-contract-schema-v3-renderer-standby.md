# P6.01 Contract schema v3 + renderer standby

Size: 3 points
Type: feat
Scope: contracts
Red: required

## Outcome

- `requesting_input` is removed from `ACTIVITY_STATES` and replaced by `standby` in `packages/contracts/src/animation-state.ts`.
- `STATE_JSON_SCHEMA_VERSION` is bumped to `3` in `packages/contracts/src/state-json.ts`.
- `StateJsonV1` gains three optional fields: `attention` (object with `reason_kind`, `summary`, `created_at`, `expires_at`), `tool_command` (string), and `work_mode` (enum stub).
- `RELIABLE_ACTIVITY_STATES` and `HEURISTIC_ACTIVITY_STATES` updated to reference `standby`.
- All existing test fixtures and unit tests updated — no references to `requesting_input` remain in the test suite.
- The Swift renderer (macOS app) handles `standby` as a valid `activity_state` — no crash or unknown-enum fallback when reading a v3 `state.json`.
- The renderer compiles and passes its existing test suite with no regressions.

## Red

- Add a test in `packages/contracts/src/state-json.test.ts` asserting `parseStateJson` accepts `activity_state: "standby"` and rejects `activity_state: "requesting_input"`.
- Add a test asserting `parseStateJson` accepts a payload with a fully-populated `attention` object and a payload with `attention` absent.
- Add a test asserting `parseStateJson` accepts `work_mode: "thinking"`, `"implementing"`, `"testing"`, and accepts absence of `work_mode`.
- Run `bun test` and confirm the new tests fail before any implementation.
- Commit with suffix `[red]`: `test(P6.01): standby rename + attention schema [red]`

## Green

- In `animation-state.ts`: replace `"requesting_input"` with `"standby"` in `ACTIVITY_STATES` and `RELIABLE_ACTIVITY_STATES`.
- In `state-json.ts`: bump `STATE_JSON_SCHEMA_VERSION` to `3`. Add to `stateJsonV1Schema`:
  ```ts
  attention: z.object({
    reason_kind: z.enum(["input_requested", "error_blocked", "review_ready"]),
    summary: z.string(),
    created_at: z.string().datetime({ offset: true }),
    expires_at: z.string().datetime({ offset: true }),
  }).optional(),
  tool_command: z.string().optional(),
  work_mode: z.enum(["thinking", "implementing", "testing"]).optional(),
  ```
- In the Swift renderer: add `"standby"` to the `ActivityState` enum (or equivalent string switch). Map it to the same visual treatment as `idle` until Phase 07 adds dedicated animation — the bubble (P6.08) is the primary affordance for `standby`.
- Run `bun test` — all tests pass. Run renderer build — compiles clean.

## Refactor

- Search the full repo for any remaining `"requesting_input"` string references (fixtures, docs, comments) and update them to `"standby"`. Use `grep -r "requesting_input"` to confirm zero occurrences after the change.

## Review Focus

- The `schemaVersionField` validator (`z.number().int().min(1).max(STATE_JSON_SCHEMA_VERSION)`) must accept 1, 2, and 3 — verify the max bound is updated.
- `attention.expires_at` is a datetime string, not a number — confirm the Zod validator enforces ISO 8601 with offset.
- `work_mode` is intentionally unpopulated by any hook in this phase — confirm no hook code sets it yet.
- Swift renderer: confirm the `standby` case does not throw a fatal error or silently map to a wrong animation row.
- No `requesting_input` references should remain anywhere in the repo after this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `STATE_JSON_SCHEMA_VERSION` === 3 failed (was 2); `standby` accepted failed (not in enum); attention fields failed (not in schema).
Why this path: Bundling contracts rename and renderer `standby` handling into one PR eliminates the broken-intermediate-state window where `state.json` emits `standby` to a renderer still expecting `requesting_input`. Two-language PR accepted for single-operator delivery.
Alternative considered: Separate contracts PR (P6.01) and renderer PR (old P6.07) with a documented prerequisite — rejected because the ordering constraint is operational risk with no reviewer benefit.
Deferred: `work_mode` population is Phase 07. Renderer dedicated `standby` animation row is Phase 07. Richer `attention.reason_kind` values beyond the starter set are Phase 07.
Contract note: `StateJsonV1` type name is kept despite schema version 3 — the version field is a forward-compat guard, not a type rename signal.
Swift: `ActivityState.requestingInput` renamed to `.standby`. `EXPECTED_STATE_SCHEMA_VERSION` bumped to 3. `CodexPet.rowMap` key updated — row index 3 (waving) unchanged. DemoCycleDriver, all tests, and fixtures updated.
