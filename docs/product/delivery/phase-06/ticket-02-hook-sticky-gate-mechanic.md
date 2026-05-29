# P6.02 Hook: sticky gate mechanic

Size: 2 points
Type: feat
Scope: hook
Red: required

## Outcome

- SoA gate states (`hyped`, `calling_for_backup`, `waiting`, `celebrating`, `nervous`, `focused`, `panicking`, `ascended`) persist in `state.json` through subsequent tool_use events.
- A gate state is cleared only when: (a) a new SoA gate event fires, or (b) a `session_end` / `stop` event arrives.
- `.hook-counters.json` gains a `last_gate: { state: ActivityState, fired_at: string } | null` field.
- When `last_gate` is set and the incoming event is a tool_use (not a gate or session_end), `runHook` emits `last_gate.state` rather than the heuristic result.
- `fired_at` is an ISO 8601 timestamp of when the gate originally fired — unused in Phase 06, present for Phase 07 gate TTL.

## Red

- In `packages/cli/src/hook-binary.test.ts`, add a test that:
  1. Sends a `ticket_started` gate event via `runHook` → confirms `state.json` shows `hyped`.
  2. Sends a subsequent `Bash` tool_use event → confirms `state.json` still shows `hyped` (not `idle`).
  3. Sends a `Stop` event → confirms `state.json` shows `standby` (gate cleared).
- Add a second test confirming a new gate event (`subagent_invoked`) overwrites the sticky gate to `calling_for_backup`.
- Run `bun test` and confirm the new tests fail.
- Commit: `test(P6.02): sticky gate persists through tool_use [red]`

## Green

- Add `last_gate: { state: ActivityState; fired_at: string } | null` to the `Counters` type and `parseSoaTail`/`readCounters`/`writeCounters` logic.
- In `runHook`: after `classifyEvent` and the SoA tail read, apply stickiness:
  - If a fresh SoA gate was read this invocation: set `last_gate = { state: fresh.state, fired_at: now.toISOString() }`.
  - Else if the incoming event is a `session_end` / `stop`: clear `last_gate = null`.
  - Else if `last_gate !== null` and the classified state is a heuristic (tool_use): override `activityState` with `last_gate.state`.
- Write updated counters (including `last_gate`) at end of lock.

## Refactor

- Extract the gate-class detection (`SOA_GATE_TO_STATE` values) into a `Set<ActivityState>` constant `GATE_STATES` — used by the stickiness check to confirm a state is gate-class before persisting it.

## Review Focus

- The stickiness override must happen _after_ the SoA tail read, not before — otherwise a same-invocation gate event gets doubly applied.
- `session_end` and `stop` both clear `last_gate`; verify both event kinds are handled (current `rawHookKind` maps both to `"session_end"`).
- `fired_at` should be the timestamp of the gate event itself, not the current hook invocation time — or current time if the gate came from the SoA tail (no separate timestamp available there). Document this as a known approximation in Rationale.
- `parseSoaTail` / `readCounters` must not crash on old counters files that lack `last_gate` — treat missing as `null`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: Storing `last_gate` in `.hook-counters.json` avoids an extra `state.json` read per hook invocation. Both files are written inside `withHomeLock` so no race window exists.
Alternative considered: Re-read `state.json` on every hook invocation to get current gate — rejected due to extra I/O on hot path and coupling stickiness to renderer output rather than hook intent.
Deferred: Gate TTL (auto-expiry of stale `last_gate` after N hours) is Phase 07 — `fired_at` is present for that purpose.
Contract note: `fired_at` is always `opts.now.toISOString()` (hook invocation time) regardless of gate source. The direct-hook-input case has no separate event timestamp in the hook payload shape, so the spec's intended "timestamp of the gate event itself" cannot be recovered for direct input — `now` is used universally. The approximation is not SoA-tail-specific as the spec draft implied; Phase 07 TTL consumers should treat `fired_at` as the invocation-time lower bound.
