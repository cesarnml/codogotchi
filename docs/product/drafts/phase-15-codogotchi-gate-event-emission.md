# Phase 15 Draft — Codogotchi Gate Event Emission

_Drafted: 2026-05-23_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: codogotchi Phase 1 delivery + `soa-event-feed.md` contract cross-reference_

---

## Thesis

Codogotchi's menubar pet changes animation based on what the AI agent is doing.
The hook binary that drives it reads `.soa/events.ndjson` to obtain explicit
orchestrator gate signals — but SoA has never written to that file. The contract
doc (`docs/contracts/soa-event-feed.md` in the codogotchi repo) declares SoA as
the producer; the codogotchi hook is already wired to consume it. The wire is
unconnected at the SoA end.

Right now the hook falls back entirely to Claude/Codex tool-call heuristics:
edit → `implementing`, bash+test-runner → `running_tests`, stop → `idle`. Mali
never enters the orchestrator-specific states (`hyped`, `celebrating`,
`calling_for_backup`, `panicking`, etc.) because SoA never emits a signal.

This phase adds the writer. When SoA runs in a project directory it appends one
NDJSON line to `.soa/events.ndjson` at each recognized gate point. The hook
binary picks it up on the next invocation and Mali changes state. No new
inter-process protocol; no polling daemon; no coupling beyond a local file.

---

## The Problem

### The emit path is missing

`tools/delivery/notifications.ts` already builds the right business-level events
(`ticket_started`, `ticket_completed`, `pr_review_window_opened`,
`review_recorded`, etc.) and ships them to Telegram. The event taxonomy is
correct. What's missing is a parallel write path that appends the same moments
to `.soa/events.ndjson` in the format the codogotchi contract expects.

The contract format is simple — one JSON object per line:

```json
{
  "name": "ticket_started",
  "ts": "2026-05-23T14:00:00.000Z",
  "plan_key": "phase-15",
  "ticket_id": "P15.01"
}
```

Fields: `name` (string), `ts` (ISO-8601 string), `plan_key` (optional string),
`ticket_id` (optional string). Unknown extra fields pass through. The consumer
(codogotchi hook) validates with zod `.passthrough()` — malformed lines are
silently skipped.

### The recognized events that have clear SoA emit points

The codogotchi contract maps 9 SoA event names to animation states. Five of
them have direct counterparts in the existing SoA notification system with
clean, tested emit points:

| SoA event name            | Activity state       | SoA command / trigger                                |
| ------------------------- | -------------------- | ---------------------------------------------------- |
| `ticket_started`          | `hyped`              | `deliver start` / `advance` → ticket → `in_progress` |
| `ticket_completed`        | `celebrating`        | `advance` → ticket → `done`                          |
| `pr_review_window_opened` | `waiting`            | `open-pr` → review window ready                      |
| `review_clean_recorded`   | `celebrating`        | `record-review clean` / `poll-review` → clean        |
| `subagent_invoked`        | `calling_for_backup` | subagent runner invocation in `subagent-runner.ts`   |

Four additional events exist in the contract but have no clear SoA-side emit
point today and are deferred to a later phase:

| SoA event name        | Activity state | Defer rationale                                                  |
| --------------------- | -------------- | ---------------------------------------------------------------- |
| `verification_failed` | `panicking`    | Verify gate runs outside orchestrator control; detection unclear |
| `risky_diff_detected` | `nervous`      | Static-analysis trigger undefined; requires heuristic work       |
| `flow_state_entered`  | `focused`      | No current orchestrator detection of "flow state"                |
| `stage_advanced`      | `ascended`     | No current SoA stage-advance command or event                    |

---

## Committed Scope

### 1. SoA event feed writer

Add `tools/delivery/soa-event-feed.ts`:

- `appendSoaEvent(projectRoot: string, event: SoaEventLine): Promise<void>` —
  appends one NDJSON line (JSON + `\n`) to `${projectRoot}/.soa/events.ndjson`,
  creating the directory if absent. Atomic via temp-file + rename is not
  required here (append to an existing file is atomic enough for a single writer
  process). Uses `fs/promises` `open` with `a` flag.
- `buildSoaEventLine(name: string, opts?: { plan_key?: string; ticket_id?: string; payload?: Record<string, unknown> }): SoaEventLine` —
  constructs the line object with `ts: new Date().toISOString()`.
- No external deps. No Zod on the write path (we construct the object; the
  consumer validates on read).

The file is `.gitignore`-able from the consumer repo's perspective — SoA should
document in `AGENTS.soa.md` that `.soa/` is a local-only sidecar directory and
should be in `.gitignore`. This phase adds that note.

### 2. Emit points — five events

Emit calls are added at the following CLI command boundaries. All emits are
**best-effort** (`try/catch`, silent on error) — a failed write must never
abort a delivery command.

**`ticket_started`**

- In `cli.ts` at the `start` command, after the state transition succeeds.
  `plan_key` from `state.planKey`, `ticket_id` from the ticket being started.
- Also in `advance` when a ticket transitions from non-`in_progress` to
  `in_progress` (mirrors `eventsForAdvanceCommand` in `notifications.ts`).

**`ticket_completed`**

- In `advance` when a ticket transitions to `done` (mirrors
  `eventsForAdvanceCommand`). Same `plan_key` / `ticket_id` sourcing.

**`pr_review_window_opened`**

- In `cli.ts` at the `open-pr` command, after `buildReviewWindowReadyEvent`
  returns a non-undefined event (i.e., PR URL and `prOpenedAt` are both set).

**`review_clean_recorded`**

- In `cli.ts` at the `record-review` command when `outcome === 'clean'`.
- Also in `poll-review` when the review resolves to `clean` (mirrors
  `eventsForPollReviewCommand`).

**`subagent_invoked`**

- In `subagent-runner.ts`, immediately before the runner subprocess is spawned.
  `payload` can carry `runnerKind` for debugging.

### 3. Project root resolution

The writer needs the project root — the same directory the consumer reads from.
SoA's `cli.ts` always operates in a project directory (it reads
`orchestrator.config.json` and `.soa-delivery-state.json` from cwd). Pass
`process.cwd()` as `projectRoot` to all emit calls in `cli.ts`. In
`subagent-runner.ts`, `cwd` is already threaded through — use it.

### 4. `.gitignore` documentation

Add `.soa/` to the gitignore example in `AGENTS.soa.md` and add a one-line
comment explaining it is codogotchi's local sidecar — not a deliverable.
Consumer repos that already have `.soa/` in their gitignore are unaffected.

---

## Defers

- **`verification_failed`**: requires detecting when `bun run verify` exits
  non-zero inside an orchestrated delivery step. SoA currently does not capture
  the verify exit code as a structured event. Deferred until the verify gate is
  formalized as a first-class orchestrator step.
- **`risky_diff_detected`**: requires diff size / risk heuristics. Out of scope
  for Phase 15.
- **`flow_state_entered`**: no current orchestrator model of "flow state".
  Deferred.
- **`stage_advanced`**: no current stage-advance command or concept in SoA.
  Deferred.
- **File rotation / truncation**: codogotchi's consumer handles inode mismatch
  and resets the read offset. SoA just appends; rotation is not its problem.
- **Cross-repo fan-out**: one events file per project root, per the contract.
  No multi-root broadcasting.

---

## Phase Goal

This phase should leave the product in a state where:

- Running `bun run deliver start P15.01` in a consumer repo causes
  `.soa/events.ndjson` to gain a `ticket_started` line within the same command
  invocation.
- Running `bun run deliver advance` when a ticket transitions to `done` causes a
  `ticket_completed` line to appear.
- Running `bun run deliver open-pr` appends `pr_review_window_opened` when the
  review window is real.
- Recording a clean review appends `review_clean_recorded`.
- Invoking a subagent appends `subagent_invoked`.
- A codogotchi hook binary running against the same project directory picks up
  these lines on the next Claude/Codex tool-call invocation and drives Mali into
  the corresponding animation state.
- No delivery command aborts due to an event-feed write failure.
- `.soa/events.ndjson` is documented in `AGENTS.soa.md` as a local-only sidecar.

---

## Cross-repo traceability

The codogotchi contract doc at
`docs/contracts/soa-event-feed.md` calls out:

> _"Cross-reference: the SoA-side emit ticket should link back to this doc for
> traceability."_

The Phase 15 implementation plan and ticket-01 should include a direct link to
that file. The codogotchi `soa-event-feed.md` does not need to change — the
contract is already correct; SoA just needs to fulfill it.

---

## Suggested ticket breakdown (for `/soa decompose`)

| #   | Title                                                      | Scope                                                                                |
| --- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 01  | Add `soa-event-feed.ts` writer module                      | New file; unit tests for `appendSoaEvent` and `buildSoaEventLine`; path construction |
| 02  | Emit `ticket_started` and `ticket_completed`               | Wire into `cli.ts` `start` and `advance` commands; integration test against tmp dir  |
| 03  | Emit `pr_review_window_opened` and `review_clean_recorded` | Wire into `open-pr` and `record-review` / `poll-review` paths                        |
| 04  | Emit `subagent_invoked`                                    | Wire into `subagent-runner.ts` before subprocess spawn                               |
| 05  | `.gitignore` doc and AGENTS.soa.md update                  | One-paragraph note; gitignore example line                                           |
