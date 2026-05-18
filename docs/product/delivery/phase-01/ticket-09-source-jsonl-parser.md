# P1.09 Source: shared JSONL parser (Claude Code + Codex)

Size: 2 points
Type: feat
Scope: engine

## Outcome

- `packages/engine/src/sources/jsonl-parser.ts` exports `readJsonlSignals(opts: { source: "claude" | "codex"; rootDir: string; since: Date }): Promise<JsonlSignalSet>` that:
  - Walks the per-source root (`~/.claude/projects/**/*.jsonl` for Claude; analogous for Codex).
  - Streams each `.jsonl` file line-by-line (no whole-file reads — files can be large).
  - Extracts token counts (and any other fields the engine needs) per source's schema.
  - Returns an aggregated `JsonlSignalSet` (counts, per-project breakdown, last-event timestamp).
  - Tolerates malformed lines (skip with debug-log entry, do not throw).
- This module is the only place that touches the filesystem for JSONL sources. Pure engine functions consume the returned `JsonlSignalSet` only.
- `source: "claude"` and `source: "codex"` share parser internals via a source-config table; both formats are handled by the same code path.
- `bun test packages/engine/src/sources/jsonl-parser.test.ts` covers: fixture files for each source, malformed-line skip, `since`-cutoff filtering, empty directory, missing root directory.

## Red

- Write failing tests with fixture `.jsonl` files in `packages/engine/test/fixtures/jsonl/{claude,codex}/`.
- Assert returned counts and last-event timestamps.
- Commit: `test(P1.09): JSONL parser for Claude Code + Codex [red]`.

## Green

- Implement the parser using Bun's file APIs and line-streaming.
- Source-config table maps source name → `{ rootGlobDefault, tokenField, projectField, ... }`.
- Skip malformed lines silently (return `{ parseErrors: number }` in result for visibility, but do not throw).

## Refactor

- Extract source-config table to a constant if both sources end up reading from it.
- Only refactor what this ticket touches.

## Review Focus

- Streaming, not full-file reads. Reviewer confirms no `readFileSync` or `await Bun.file(...).text()` on potentially-large files.
- `since` cutoff is applied early (skip line if timestamp is before cutoff) to keep cost bounded on first sync of a long-running project.
- Source-config table is the single source of truth for per-format differences; the actual parse loop is shared.
- Malformed-line behavior is documented — silent skip with counter, not throw.
- Fixture files are realistic enough to catch regressions if either format changes shape upstream.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **Codex per-file project state vs. early `since` cutoff (subagent-review).** The first implementation skipped any line whose raw timestamp predated `since` before letting the source-config extractor see it. For Claude that is fine — every line carries its own `cwd`. For Codex it is not: `session_meta` lines often have an older timestamp than the in-window `token_count` events that follow them in the same session file, so dropping the meta early left `currentProject` unset and the in-window events bucketed into `<unknown>`. The early cutoff was removed; the post-extract `event.timestamp < sinceIso` check still excludes pre-cutoff events from aggregation. Cost-bounding is preserved in practice because the bulk of work (token math, per-project bucketing, `lastEventAt` update) only runs once an event survives that post-extract check.
- **Tokens computation differs by source.** Claude sums `input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens` from `message.usage`. Codex uses `payload.info.last_token_usage.total_tokens` per `event_msg` of type `token_count`. The source-config table is the single place either field name appears.
