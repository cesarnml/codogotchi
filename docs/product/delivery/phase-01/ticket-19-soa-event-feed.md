# P1.19 SoA gate signal mapping (defensive read of `.soa/events.ndjson`)

Size: 2 points
Type: feat
Scope: cli

## Outcome

- `docs/contracts/soa-event-feed.md` defines the NDJSON line schema (event name, ts, plan key, ticket id, optional payload) and the mapping table from SoA events to animation states (`hyped`, `focused`, `nervous`, `waiting`, `celebrating`, `ascended`, `calling_for_backup`, `panicking`).
- `packages/contracts/src/soa-events.ts` exports the zod schema for a SoA event line + the mapping table as typed data.
- `packages/engine/src/sources/soa.ts` exports `watchSoaEvents(rootDir: string, onEvent: (event) => void)`: polls `${rootDir}/.soa/events.ndjson` every 250ms, parses new lines (tracks inode + offset), invokes `onEvent`. Silent skip if file absent. Malformed lines logged-and-skipped, not throwing.
- Hook binary (P1.18) is extended to: resolve the SoA events path from `$CLAUDE_PROJECT_DIR/.soa/events.ndjson` (or `$CODEX_PROJECT_DIR/...`, or `cwd/...`), watch for events when present, merge the resulting state with Claude/Codex-derived state (SoA events take precedence when fresh, fall back to tool-call inferred state otherwise).
- Tests cover: file absent (silent), file present with valid lines (each maps correctly), malformed line (skip + log), file rotated/truncated mid-watch (handles inode change), precedence (fresh SoA event overrides tool-call state).

## Red

- Write failing tests with fixture `.soa/events.ndjson` files in test tempdirs.
- Commit: `test(P1.19): SoA event feed mapping and defensive read [red]`.

## Green

- Implement the watcher + mapper. Use inode + offset tracking for tail semantics; fall back to size comparison if inode is unavailable.
- Wire into hook binary's classification pipeline.

## Refactor

- Extract a tiny "tail-by-poll" helper if it stands alone cleanly.
- Only refactor what this ticket touches.

## Review Focus

- Defensive: file/dir absent = silent skip, no log noise. Reviewer simulates a fresh repo with no `.soa/` dir and confirms.
- Path resolution priority: `$CLAUDE_PROJECT_DIR` > `$CODEX_PROJECT_DIR` > `cwd`. Documented.
- No writes to `.soa/` from codogotchi — this is read-only consumption. Reviewer greps to confirm.
- No coupling to SoA's actual implementation — codogotchi only reads what the contract doc specifies. If SoA's emit ticket lands later, this still works as soon as the file appears.
- Precedence rule between SoA and tool-call inferred state is explicit and tested.
- The contract doc mirror should be cross-referenced from the SoA repo's own plan (not in scope for this repo, but linked from `docs/contracts/soa-event-feed.md` for traceability).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

### Implementation notes (P1.19)

- **Reader is pure I/O.** `readSoaEventsSince` in `packages/engine/src/sources/soa.ts` tail-reads `${root}/.soa/events.ndjson` since the previous `(inode, offset)` and silently returns no events when the file is absent. Malformed lines are skipped without log noise. The hook never throws on SoA input — the file is untrusted external state.
- **`watchSoaEvents` is for future renderers, not the hook.** The hook is short-lived (<50ms target), so it does a one-shot tail-read per invocation. `watchSoaEvents` exists as a 250ms poll wrapper for any future long-running renderer that subscribes to the stream.
- **Tail offset stops at the last newline.** Trailing partial lines (no `\n`) are not consumed so the next invocation re-reads them once SoA finishes flushing. This avoids dropping or duplicating events on partial writes.
- **Inode-aware rotation handling.** If the prior sidecar inode does not match the current file inode, the reader resets to offset 0 and re-reads in full. It also resets when the prior offset is past the current size (truncation).
- **Sidecar shape extended.** `.hook-counters.json` now carries `{read_run, soa_tail}`. Validation coerces unrecognized fields back to safe defaults (counter 0, tail `null`) so a corrupt sidecar never blocks classification.
- **Precedence resolved at the hook layer, not in `classifyEvent`.** `classifyEvent` still maps raw stdin events as before. `runHook` then reads fresh SoA events and overrides `activity_state` + `source_event` to the latest mapped SoA event when any exist. SoA events with unrecognized names do not override tool-stream classification (per contract).
- **Path resolution priority.** `$CLAUDE_PROJECT_DIR` > `$CODEX_PROJECT_DIR` > `cwd`. Mirrored in `docs/contracts/soa-event-feed.md`. `resolveSoaRoot` is a pure function for testability — the hook injects `env` and `cwd` for tests but defaults to `process.env` and `process.cwd()` at runtime.
- **No writes to `.soa/`.** The engine source and the hook only read. The contract doc states the boundary and includes a grep recipe to verify in CI later.
- **Schema `passthrough()`.** The line schema is intentionally permissive on unknown fields so the SoA producer can add metadata without breaking codogotchi. Only `name` and `ts` are required for parsing; mapping requires `name` to be in `SOA_EVENT_NAMES`.
