# P7.02 Hook-binary pure classifier — drop events.ndjson reader, full §7 read/explore buckets

Size: 3 points
Type: feat
Scope: hook
Red: required

## Outcome

- `packages/cli/src/hook-binary.ts` no longer reads `.soa/events.ndjson`: the `SOA_GATE_TO_STATE` map, `last_gate`/`soa_tail` counters, `parseSoaTail`, `pickLatestMappedSoaEvent`, and the `resolveSoaRoot`/`readSoaEventsSince` calls are removed. The hook is a pure platform-event classifier writing only `state.json`.
- `packages/engine/src/sources/soa.ts` (the events.ndjson reader) and its test are deleted; no `mapSoaEventToActivityState`/`SOA_EVENT_TO_ACTIVITY_STATE` references remain in the hook path. `soa-events.ts` mapping is removed or reduced to nothing the hook imports.
- The classifier emits the v4 hook vocabulary per research §6/§7:
  - `Edit`/`Write`/`MultiEdit` and Bash write/mutate commands → `implementing`
  - Bash test/lint/format runners → `testing`
  - Bash read/search (`grep`/`rg`/`find`/`ls`/`cat`/`tail`/`head`/`wc`/`awk`/`git log`/`git diff`) → `thinking`
  - `Read` ×1–2 (streak) → `reading`; `Read` ×3+ → `cramming` (reuses the existing `readRun` counter, reset on write tools)
  - `Stop` success → `standby`; no-signal/TTL floor → `idle`
- No deleted state name (`running-tests`, `reviewing`, `pushing`, gate states) is ever emitted.

## Red

- Extend `hook-binary.test.ts`:
  - Bash `grep ...` → `thinking`; `bun test` → `testing`; `sed -i ...`/redirect → `implementing`.
  - `Read` once → `reading`; three `Read`s in a streak → `cramming`; a write tool resets the streak.
  - `Stop` (success) → `standby`.
  - A test asserting no `.soa`/events.ndjson read path is invoked (e.g., the SoA root resolver is no longer called / removed).
- Run the suite; confirm failures.
- Commit `[red]`: `test(hook): pure §7 classifier, no events.ndjson reader [red]`.

## Green

- Remove the SoA tail-reading machinery and engine `soa.ts`; rewrite `classifyEvent` to the §7 buckets.
- Reuse the existing `readRun` streak for `reading`/`cramming`; keep the write-tool reset.
- Smallest change to pass; do not add failure-event classification (P7.03) or touch the renderer (P7.04).

## Refactor

- Delete now-orphaned imports, types (`SoaTailState`, `LastGate`), and counter fields from `.hook-counters.json` handling.
- Extract the Bash command-bucket prefix lists as named constants if not already.

## Review Focus

- Complete removal: no lingering `events.ndjson`, `resolveSoaRoot`, `readSoaEventsSince`, or `SOA_GATE_TO_STATE` references in the hook or engine.
- `readRun` streak semantics for `reading`→`cramming` match research §7 (×1–2 vs ×3+, reset on write).
- Bash bucket classification covers the documented prefixes; unknown Bash falls to `implementing` (not `idle`).
- The hook writes only `state.json` and never touches `gate.json`.

## Rationale

Red first: `Read ×1 → reading` (was `idle`) and `Read ×3 → cramming` (was `thinking`) failed. Then `sed -i → implementing` (was `thinking` since `sed` was in the thinking bucket). Then SoA non-override test failed (SoA events still influenced state).

Why this path: Full removal of SoA machinery in one pass. The `Counters` type shrank to `{ read_run: number }`, removing `soa_tail` and `last_gate`. `RunHookOptions` dropped `env`/`cwd` (only used for SoA root resolution). `REVIEWING_BASH_PREFIXES` renamed to `THINKING_BASH_PREFIXES`, `sed` removed (not in §7 spec), `git log`/`git diff` added.

Alternative considered: Keeping `sed` in the thinking bucket — rejected because §7 spec lists the explicit thinking command set and `sed` is not in it; `sed -i` is a write command and `sed` without `-i` is an edge case best handled by implementing as default.

Deferred: `waiting_for_input`/PermissionRequest wiring — platform-hooks phase. Lint/format runner exhaustive list (e.g. `tsc --noEmit`, `cargo clippy`) — §7 says TBD; current test-runner prefix list covers the documented cases.

Contract note: `engine/src/sources/soa.ts` and its test were deleted. Engine `index.ts` no longer re-exports the soa source. `contracts/soa-events.ts` is retained (no hook imports it; the file may be useful to the SoA side that still writes `state.json`).
