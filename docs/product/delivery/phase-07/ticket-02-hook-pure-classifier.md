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

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
