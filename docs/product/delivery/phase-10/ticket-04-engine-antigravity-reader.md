# P10.04 Engine — Antigravity token reader

Size: 2 points
Type: feat
Scope: engine
Red: required

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

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [smallest acceptable]
Alternative considered: [separate parser module vs extending jsonl-parser]
Deferred: [Cursor/VS Code token reading — not locally available]
Contract note: [record any metadata deviation]
