# P6.04 Hook: standby attention payload + tool.command persistence

Size: 2 points
Type: feat
Scope: hook
Red: required

## Outcome

- When `runHook` writes `activity_state: "standby"`, it also writes an `attention` object with `reason_kind: "input_requested"`, a fixed summary string, `created_at: now`, and `expires_at: now + 2h`.
- When `runHook` writes `activity_state: "errored"`, it also writes `attention` with `reason_kind: "error_blocked"`, a fixed summary string, and `expires_at: now + 30m`.
- For all other states, `attention` is absent from `state.json`.
- For every Bash or Shell tool_use event with a defined command string, `tool_command` is written to `state.json` (the raw command string). Absent for non-Bash/Shell events and Bash/Shell events with no command string.
- Summary strings:
  - `input_requested`: `"Waiting for your input"`
  - `error_blocked`: `"Something went wrong — agent stopped"`

## Red

- In `packages/cli/src/hook-binary.test.ts`, add tests for `runHook` (integration-style, using temp home dir):
  - Stop event → `state.json` has `attention.reason_kind === "input_requested"`, `attention.summary === "Waiting for your input"`, `attention.expires_at` is ~2h after `updated_at`.
  - Stop event with `is_error: true` → `attention.reason_kind === "error_blocked"`, `expires_at` is ~30m after `updated_at`.
  - Edit tool_use event → `attention` is absent from `state.json`.
  - Bash tool_use with command `"grep foo"` → `state.json` has `tool_command === "grep foo"`.
  - Edit tool_use → `tool_command` is absent from `state.json`.
- Run `bun test` and confirm the new tests fail.
- Commit: `test(P6.04): attention payload + tool_command persistence [red]`

## Green

- Add TTL constants: `STANDBY_TTL_MS = 2 * 60 * 60 * 1000` and `ERRORED_TTL_MS = 30 * 60 * 1000`.
- Add `buildAttention(state: ActivityState, now: Date): AttentionPayload | undefined`:
  - `standby` → `{ reason_kind: "input_requested", summary: "Waiting for your input", created_at: now.toISOString(), expires_at: new Date(now.getTime() + STANDBY_TTL_MS).toISOString() }`
  - `errored` → `{ reason_kind: "error_blocked", summary: "Something went wrong — agent stopped", created_at: now.toISOString(), expires_at: new Date(now.getTime() + ERRORED_TTL_MS).toISOString() }`
  - All others → `undefined`
- In `runHook`, after determining final `activityState`, call `buildAttention` and include the result in the `StateJsonV1` payload (omit key when `undefined` so Zod `.optional()` round-trips cleanly).
- For `tool_command`: when `sourceEvent.kind === "tool_use"` and `(sourceEvent.name === "Bash" || sourceEvent.name === "Shell")`, include `tool_command: classified.command` in the payload (where `classified.command` is surfaced from `ClassifyResult` — add it if not already present).

## Refactor

- `ClassifyResult` currently does not expose `command`. Add `command?: string` to the type and thread it through `classifyEvent` return value so `runHook` can read it without re-parsing `input`.

## Review Focus

- `expires_at` arithmetic: confirm `new Date(now.getTime() + TTL_MS)` produces the correct ISO string. Test the 2h and 30m cases explicitly.
- `tool_command` should not appear on gate events or session events — only `tool_use` kind with Bash/Shell name.
- `attention` must be absent (not `null`, not `{}`) for non-standby/errored states — verify Zod round-trip strips `undefined` keys.
- Summary strings are v1 copy — they will be revisited in Phase 07. Document the copy choices in Rationale so future-you has context.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `attention` was `undefined` on the Stop-event test — confirmed three tests failed before implementation.
Why this path: Fixed summary strings are sufficient for Phase 06. Claude Code Stop provides no message content; Cursor stop provides only status enum. Platform-conditional rich summaries deferred to Phase 07 when Phase 07 also redesigns gate vocabulary.
Alternative considered: Reading `transcript_path` JSONL to extract last assistant message for richer summary — rejected, adds async I/O to hot path and only works on Claude Code, not Cursor/Codex.
Deferred: Richer summaries using Codex `last_assistant_message` or Claude Code transcript read — Phase 07. `review_ready` reason_kind (for SoA review completion signals) — Phase 07.
Contract note: `ClassifyResult.command` is only set in Bash/Shell branches where `command !== undefined`; the `command === undefined` early return intentionally omits it so `runHook` can distinguish "no command string" from "not a Bash/Shell event". `attention` key is entirely absent (not `null`) for non-standby/errored states via the spread-operator conditional — Zod `.optional()` round-trips cleanly.
