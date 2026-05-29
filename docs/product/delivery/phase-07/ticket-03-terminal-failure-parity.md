# P7.03 Terminal failure parity — StopFailure + Cursor error classification

Size: 3 points
Type: feat
Scope: hook
Red: required

## Outcome

- The Claude Code installer registers `StopFailure`: `CODOGOTCHI_EVENTS` in `packages/cli/src/hooks.ts` includes `StopFailure` alongside `PreToolUse` and `Stop`; `hooks status` install detection accounts for it.
- The hook-binary classifies terminal API failures as `errored`, in a branch evaluated before the generic tool_use heuristics:
  - `hook_event_name` ∈ `StopFailure` (any `error` value: `rate_limit`, `authentication_failed`, `billing_error`, `server_error`, `max_output_tokens`, `unknown`, …) → `errored`
  - Cursor `stop` with `status: "error"` → `errored`
  - Cursor `postToolUseFailure` with `!is_interrupt` → `errored`
  - `Stop` + `stop_reason: "max_tokens"` remains an `errored` path (unchanged)
- Codex: no `StopFailure` equivalent is registered; the discovery gap is captured as a documented runbook note (carried into P7.05), not faked.
- Failure classification does not regress the success paths: a normal `Stop` still yields `standby`.

## Red

- Extend `hooks.test.ts`: the Claude installer writes `StopFailure` into the hook config; idempotent re-install detects it as present.
- Extend `hook-binary.test.ts` with fixtures:
  - a `StopFailure` payload (`error: "rate_limit"`) → `errored`
  - Cursor `stop` `status:"error"` → `errored`
  - Cursor `postToolUseFailure` `is_interrupt:false` → `errored`; `is_interrupt:true` → not `errored`
  - a normal `Stop` (success) still → `standby` (no regression)
- Run the suite; confirm failures.
- Commit `[red]`: `test(hook): terminal failure parity → errored [red]`.

## Green

- Add `StopFailure` to the Claude event list and installer write/detect paths.
- Add the failure-classification branch in `hook-binary.ts` ahead of the generic heuristics.
- Smallest change to pass; do not register Cursor/Codex `PermissionRequest` (deferred) or alter §7 buckets.

## Refactor

- Centralize the terminal-failure detection predicate so Claude/Cursor branches share one `errored` decision point.
- Persist the platform-native failure field (`error`/`status`/`failure_type`) into the transition log only if it falls out cheaply; do not expand scope otherwise.

## Review Focus

- `StopFailure` runs *instead of* `Stop` — confirm the classifier does not depend on a `Stop` also arriving for rate-limit cases.
- Failure branch precedence: it must win over tool_use heuristics but stay below SoA gate precedence (gates are renderer-side now, so this is purely about hook state).
- `is_interrupt` handling for `postToolUseFailure` (user-initiated interrupt is not an `errored`).
- Codex gap is documented, not synthesized into a fake `errored`.

## Rationale

Red first: `StopFailure` payload → `errored` failed (branch not in classifier). Cursor `stop` with `status:"error"` failed (only `is_error` and `stop_reason` were checked). `postToolUseFailure` failed (event not handled). Then Claude installer test failed because `StopFailure` was not in `CODOGOTCHI_EVENTS`.

Why this path: Minimal branches — three new cases added before the existing Stop branch. `StopFailure` always errors; `postToolUseFailure` errors only when `is_interrupt !== true`; Cursor `stop` with `status:"error"` added to the existing Stop branch. `rawHookKind` maps `stopfailure` → `session_end` and `posttoolusefailure` → `tool_use`. `CODOGOTCHI_EVENTS` extended to `["PreToolUse", "Stop", "StopFailure"]` — installer and detection loops pick it up automatically.

Alternative considered: Separate function `isTerminalFailure(input)` that encapsulates all failure detection paths — rejected because the three cases have different non-failure branches (StopFailure has none; postToolUseFailure skips when is_interrupt; stop/Stop has the success→standby path), making a single predicate awkward.

Deferred: Codex `StopFailure` equivalent — no documented hook surface; gap noted in P7.05 docs. Cursor `PermissionRequest` — deferred per implementation plan.

Contract note: `HookInput` gained three new optional fields: `error`, `status`, `is_interrupt`. These widen the type without breaking callers.
