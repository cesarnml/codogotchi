# P10.04 Engine — Antigravity token reader

Size: 2 points
Type: feat
Scope: engine
Red: skip

## Outcome

- The JSONL signal reader gains an `antigravity` source: it parses Antigravity's local conversation JSONL and returns the same `JsonlSignalSet` shape (`totalTokens`, `events`, `lastEventAt`, `perProject`).
- The Antigravity transcript root is resolved (env override + default path, mirroring `claudeRoot`/`codexRoot`).
- Token extraction maps Antigravity's payload fields to input/output token counts with per-event timestamps.
- Cursor and VS Code Copilot are explicitly documented (code comment + contract note) as **non-token sources** (cloud-side usage), so no reader is attempted for them.

## Red

- Failing `vitest` against a checked-in Antigravity JSONL fixture: expected `totalTokens` and `lastEventAt`; an unparseable/foreign line increments `parseErrors` without throwing; empty/missing dir returns a zero set (no throw).
- Confirm failures; commit `test(P10.04): antigravity jsonl token reader [red]`.

## Green

- Add the `antigravity` `SourceConfig.extract` and source wiring; smallest change to pass the fixture.

## Refactor

- Factor shared extraction helpers if Antigravity and Claude/Codex overlap; keep the `JsonlSource` union tidy.

## Review Focus

- Fixture realism — use a representative Antigravity JSONL line shape; note where it was captured.
- Timestamp parsing and `lastEventAt` correctness (feeds `last_activity_at`).
- **Stop condition:** if Antigravity's local JSONL does not actually carry token counts, pause and fall back to Antigravity HP-only; record the scope change.

## Rationale

**Stop condition triggered — scope changed to documentation-only.**

Investigated Antigravity's local transcript format before writing any code.
The `agy` CLI (Antigravity) stores conversation transcripts at:
`~/.gemini/antigravity-cli/brain/<conversationId>/.system_generated/logs/transcript.jsonl`

These JSONL files contain step-based events (`step_index`, `source`, `type`, `status`,
`created_at`, `content`) with types such as `USER_INPUT`, `CONVERSATION_HISTORY`,
`PLANNER_RESPONSE`, `RUN_COMMAND`, `GREP_SEARCH`, `LIST_DIRECTORY`, etc.
**No message type carries token count fields** — confirmed by scanning all live transcript
files on 2026-06-03. Neither `transcript.jsonl` nor `transcript_full.jsonl` include any
`tokens`, `usage_metadata`, `input_tokens`, `output_tokens`, or equivalent fields.

Note: the Gemini CLI (`gemini` / `@google/gemini-cli`) stores sessions at
`~/.gemini/tmp/<hash>/chats/session-*.json` (JSON arrays, not JSONL) and its model
messages do carry `tokens: { input, output, cached, total }`. However this is a separate
product from Antigravity (`agy`) and not what Codogotchi's hooks target.

**Decision**: Fall back to Antigravity HP-only. Antigravity contributes to hearts/health
via activity hooks (already live from Phase 9) but its ring/level freezes with the same
graceful treatment as Cursor and VS Code Copilot.

**Red: skip** — no functional implementation; no testable behavior to invert. Changed from
`Red: required` to `Red: skip` to reflect the doc-only scope.

**Deferred to follow-up** (if Antigravity adds token counts to transcripts in a future
release): add an `"antigravity"` `SourceConfig.extract` to `jsonl-parser.ts` reading the
`PLANNER_RESPONSE` lines from `~/.gemini/antigravity-cli/brain/`.

Deferred: Antigravity token reading — local JSONL carries no token counts (verified 2026-06-03).
Deferred: Cursor/VS Code token reading — tokens live cloud-side (no local session JSONL written).
Contract note: `JsonlSource` remains `"claude" | "codex"` only. Antigravity, Cursor, and VS Code
are documented in a contract comment block below `SOURCE_CONFIGS` in `jsonl-parser.ts`.
