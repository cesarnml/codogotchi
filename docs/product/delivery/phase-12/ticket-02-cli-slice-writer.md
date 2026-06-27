# P12.02 CLI slice-directory writer

Size: 3 points
Type: refactor
Scope: cli
Red: required

## Outcome

- The hook (`hook-binary.ts`) writes its own slice file at `state.d/<origin>:<session_id>.json` (under `CODOGOTCHI_HOME`, default `~/.codogotchi/`) via the existing atomic tmp+rename — **never** read-modify-writing a shared file.
- The slice file content is a `schema_version: 7` slice entry (P12.01 shape) for that `(origin, session_id)`.
- The `SessionEnd` hook best-effort deletes its own slice file.
- `codogotchi status` reduces the slice directory via `globalAggregate` and prints the same status it does today for a single active session.
- **Two concurrent hook invocations from different origins produce two intact slice files** — neither clobbers the other (the correctness win; impossible with the single-file design).

## Red

- Write failing tests, behavior-first:
  - **Concurrent-write test (signature):** simulate two origins' hooks writing "simultaneously" (or interleaved) and assert both `state.d/claude_code:<sid>.json` and `state.d/codex:<sid>.json` exist with correct, independent content. This is the test that proves the refactor bought concurrency safety — it must be red against any single-`state.json` implementation.
  - A single hook event writes exactly one slice file with the v7 entry shape.
  - `SessionEnd` removes that origin/session's slice file and leaves others intact.
  - `status` over a directory of N slices prints the `globalAggregate` result.
- Confirm failures; commit `test(P12.02): slice-directory writer + concurrency [red]` before implementing.

## Green

- Resolve the session id discriminator from the hook input (Claude Code/Codex hook payloads carry a session id; reuse the existing origin classification in `hook-binary.ts`). If a platform provides no stable session id, document the fallback key (e.g. `<origin>:default`) — do not invent unbounded keys.
- Compute the slice path; write via the existing `writeStateAtomic` pattern (tmp name already PID+uuid-scoped, so cross-process renames don't collide).
- Wire `SessionEnd` → unlink own slice (best-effort, swallow ENOENT).
- Update `status` to scan `state.d/` and reduce via `globalAggregate` from `@codogotchi/contracts`.

## Refactor

- This ticket **moves the producer's on-disk output** from `state.json` to `state.d/`. Per the template: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` only if tracked *repo* files move — here the move is a runtime path under `CODOGOTCHI_HOME`, not a tracked file, so no soa-sync migration is needed (confirm and note).
- Decide and document the fate of a pre-existing legacy `~/.codogotchi/state.json` on disk: the new writer stops writing it; the new reader (P12.03) stops reading it. Leaving it vestigial is acceptable within v2_preview (fresh dev state); optionally unlink it on first slice write. Do not add migration logic for it — no real users pre-GA.

## Review Focus

- The session-id source per platform — is it stable across a thread's lifecycle, or does it churn per hook event? Churn would create orphan slices (mtime TTL in P12.03 covers stale ones, but document the expected cardinality).
- That the hook stays fire-and-forget: no locking, no read-modify-write, no blocking the host agent.
- `status` parity: same output as today for the common single-session case.
- Confirm the writer emits `schema_version: 7` and nothing still writes the old single `state.json`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
