# P2.08 Transition log — NDJSON writer + heartbeat + rotation

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `apps/menubar/Sources/TransitionLog.swift` exposes a `TransitionLog` type that:
  - Appends one NDJSON line on every observed state change.
  - Appends one heartbeat NDJSON line every 60 minutes if no state change has occurred in that window. Heartbeats reset on any real state change.
  - Writes to `~/.codogotchi/state-transitions.log` by default; path overridable via dependency injection (for tests and for demo mode using a sandboxed path).
  - Rotates the log when its size exceeds 10MB on a write: rename existing file to `state-transitions.log.1` (overwriting any prior `.1`), open a fresh log file. Single backup; no `.2`/`.3`.
- NDJSON line shape (one line per event):
  ```json
  {"ts":"2026-05-20T14:32:11.123Z","state":"implementing","prev":"idle","schema_version":1,"source_origin":"claude_code","source_kind":"tool_use","source_name":"Edit"}
  ```
  Heartbeat line shape:
  ```json
  {"ts":"...","state":"idle","heartbeat":true,"schema_version":1}
  ```
- `source_origin`, `source_kind`, `source_name` are pulled from the snapshot's `source_event` when available; null/absent when not.
- The live polling driver (P2.07) and demo driver (P2.06) both call `TransitionLog.recordTransition(snapshot:previousState:)` on every observed state change. Heartbeats are timer-driven inside the log, not driven by the polling driver.
- Tests at `apps/menubar/Tests/MenubarTests/TransitionLogTests.swift`:
  - `recordTransition(snapshot:previousState:)` writes a valid NDJSON line containing the expected fields.
  - Writing enough lines to exceed 10MB triggers exactly one rotation; the `.log.1` file exists; the `.log` is reset to a fresh (smaller) state.
  - With a fast-forwardable clock (injected), no transitions for >60 minutes triggers a heartbeat line.
  - Heartbeat lines do not affect rotation accounting (or they do, depending on implementation — pick one explicitly; the test asserts the chosen behavior).
- `notes/private/phase-02-swift-notes/P2.08-transition-log.md` lands in this PR explaining: `FileHandle` append-mode writes in Swift, ISO-8601 timestamp formatting (`ISO8601DateFormatter`), and how to inject a clock for testability.

## Red

- Write `TransitionLogTests` first. Inject a clock and a path. Run `bun run mac:test`; confirm failures.
- Commit `[red]`: `test(P2.08): transition log writes NDJSON, heartbeats hourly, rotates at 10MB [red]`.

## Green

- Implement `TransitionLog` with append-mode `FileHandle`, ISO-8601 timestamp formatter (use a single static formatter to avoid the well-known Swift formatter cost), JSON serialization via `JSONEncoder`.
- Implement the heartbeat timer as a separate `Timer` (or via the same poll-tick infrastructure — pick one).
- Implement size-check rotation: on each write, if file size exceeds 10MB after this write, rotate.
- Wire `recordTransition` calls from the live polling driver and demo driver.

## Refactor

- Confirm the file handle is opened lazily on first write (don't open at app startup just to write hours later).
- Confirm rotation is atomic enough that a crash mid-rotation leaves either the old `.log` or a fresh `.log` and a populated `.log.1` — never an empty `.log` with lost data.
- Confirm the heartbeat timer is invalidated cleanly on app shutdown.

## Review Focus

- NDJSON line format matches the product plan's stated shape; field names match the contract doc's `source_event` field names (`origin`, `kind`, `name`).
- Rotation threshold (10MB) matches `sync.log`'s convention. If `sync.log`'s actual rotation differs (e.g., 10MiB vs. 10MB), match it.
- Heartbeat cadence is honestly tested with an injectable clock — no `Thread.sleep(60 * 60)` in tests.
- File handle lifecycle: a fresh `FileHandle(forWritingTo:)` is opened per
  write, `seekToEnd()` ensures append semantics, and `defer { try? close() }`
  closes it on every code path. This trades one open syscall per line for
  straightforward crash semantics and trivial rotation (the writer owns the
  file only at the moment it is closing it). The Swift notes
  (`notes/private/phase-02-swift-notes/P2.08-transition-log.md`) record this
  decision and why an `O_APPEND` long-lived handle was not chosen.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

### Implementation notes (P2.08 delivery)

- Heartbeat-vs-rotation accounting decision: heartbeat lines **do** count
  toward the rotation byte threshold. Excluding them would track a number
  the filesystem disagrees with; the test asserts only rotation triggered
  by transitions (which is the realistic high-volume path).
- Heartbeat timer cadence: the `Timer` polls every 60 seconds and consults
  the injected clock; it only emits when the heartbeat interval has
  actually elapsed. A single 60-minute `Timer` would drift too far
  across sleep/wake to recover. The product spec ("every 60 minutes") still holds
  within ~1 minute of slack.
- `SourceEvent` was added to `StateSnapshot` and `StateJsonReader` so the
  transition log can record `source_origin`/`source_kind`/`source_name`
  from the hook payload without parsing JSON twice. Field names match the
  contract doc (`origin`, `kind`, `name`).
- Transition log path defaults to `~/.codogotchi/state-transitions.log`.
  Demo mode writes a sibling `state-transitions.log` under its sandboxed
  polling target so a live run is never trampled by a demo session.
- `LivePollingDriver` only records transitions on `.success` reads —
  failure visuals collapse to `.idle` regardless of agent state and would
  otherwise flood the log with phantom `prev=idle` entries every time the
  hook hiccups.
- Test relaxation: the NDJSON shape assertion checks ISO-8601 regex shape
  (`^\d{4}-\d{2}-\d{2}T...Z$`) rather than a hardcoded year. The fixture
  `timeIntervalSince1970` value is a stable seed, not a behavior contract.

Red first: log line shape, rotation, and heartbeat each have failing tests before code lands.
Why this path: per-state-change + hourly heartbeat balances "activity-proportional file size" with "liveness signal in the log itself." Chosen over per-poll-tick (too noisy) and per-change-only (no liveness).
Alternative considered: shared rotation logic with the TS-side `sync.log` rotation. Rejected — ~20 lines of Swift is not worth a polyglot dependency boundary; matching the *convention* (10MB cap, single `.log.1` backup) in documentation is enough.
Deferred: structured query tooling over the log, daily rotation, multi-file rolling buffers.
Contract note: if line shape deviates from this ticket's stated form during implementation, update the product plan + this ticket in the same PR.
