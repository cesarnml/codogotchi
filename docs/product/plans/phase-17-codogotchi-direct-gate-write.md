# Phase 17: Codogotchi Direct Gate Write

**Delivery status:** Delivered — Phase 17 complete (2026-05-29). All 5 tickets merged to stacked PRs #71–#75. NDJSON writer retired; `gate.json` sidecar live.

## TL;DR

**Goal:** Replace the `events.ndjson` append architecture with SoA writing gate events directly to `~/.codogotchi/gate.json`, wiring 9 gate emit points with correct timing and per-gate TTLs — the hard prerequisite for codogotchi Phase 07.

**Ships:**

- New `codogotchi-gate.ts` module: writes `~/.codogotchi/gate.json` (sidecar owned entirely by SoA); old `soa-event-feed.ts` deleted
- 9 gate emit points with "emit then action" timing, each writing `{ gate, since, expires_at, plan_key, ticket_id }` to `gate.json`
- `adversarial_review` timing fix: emits before directing the primary agent to write the adversarial prompt — not at subagent process start
- `red_tdd` / `green_tdd` gates wired to `post-red` / the TDD implementation window
- All gate TTLs set to 3m (v1 baseline for feel; tune from `state-transitions.log` after real delivery runs)
- `codogotchi.enabled` landing in son-of-anton's live `orchestrator.config.json` (field already implemented, now documented)

**Defers:**

- `advance` gate (stage_advanced via closeout-stack) — no existing emit hook in `closeout-stack.ts`; lowest-value gate (2m TTL concept); future phase
- Gate badge UI — codogotchi renderer consuming `gate.json` for visual badge is codogotchi Phase 07 scope
- Gate TTL tuning — all gates ship at 3m; adjust after observing hook bleed-through in real delivery sessions
- `subagent_invoked` as a gate — retired entirely (helper + call site deleted), replaced by `adversarial_review`

---

Phase 15 wired SoA's first write path — gate events appended to `${projectRoot}/.soa/events.ndjson`, consumed by codogotchi's hook-binary tail reader. That architecture had a fatal latency flaw: gate animations only rendered on the next hook invocation, seconds after the gate fired, and were immediately stomped by the following tool_use. Codogotchi Phase 07 retires the NDJSON reader and requires SoA to write directly to `~/.codogotchi/gate.json` — a sidecar file SoA owns exclusively, eliminating write contention with the hook-binary entirely. Phase 17 delivers that write path and the gate vocabulary that codogotchi Phase 07 depends on.

## Phase Goal

This phase should leave the product in a state where:

- Running any recognized delivery command (`start`, `advance`, `open-pr`, `poll-review`, `record-review`, `post-red`, `write-subagent-adversarial-review`) causes a valid `gate.json` entry to appear at `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`) within the same command invocation — verifiable by `cat` without codogotchi installed
- `gate.json` contains `{ gate, since, expires_at, plan_key, ticket_id }` with the correct ActivityState name, a current ISO timestamp, and an `expires_at` 3 minutes out
- The `adversarial_review` gate fires at the moment SoA directs the primary agent to begin writing the adversarial prompt — not when the subagent process starts
- Setting `codogotchi.enabled = false` in `orchestrator.config.json` suppresses all `gate.json` writes; absence of the field means enabled

## Committed Scope

### 1. `codogotchi-gate.ts` — new writer module

Replaces `soa-event-feed.ts` entirely. `soa-event-feed.ts` is deleted; no deprecated exports preserved.

`writeGateEvent(config, gate)` writes `gate.json` to `$CODOGOTCHI_HOME` (resolved via `process.env.CODOGOTCHI_HOME ?? join(homedir(), '.codogotchi')`). File format:

```json
{
  "gate": "ticket_started",
  "since": "<ISO>",
  "expires_at": "<ISO + 3m>",
  "plan_key": "phase-17",
  "ticket_id": "P17.01"
}
```

`plan_key`/`ticket_id` are carried for the deferred badge UI and `state-transitions.log` auditing — the emit sites already hold them.

Best-effort write: all errors are caught and silently discarded — no delivery command aborts due to a `gate.json` write failure. Creates `~/.codogotchi/` directory if absent.

Gate names written are the codogotchi Phase 07 schema v4 ActivityState values — the consumer contract. `gate.json` is owned entirely by SoA; the codogotchi hook-binary never writes to it.

### 2. 9 gate emit points — "emit then action"

All gates fire **before** directing the agent to the relevant action, extending the effective animation window.

| Gate (ActivityState) | Emit site                                                                  | Emit moment                                                                                         |
| -------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `ticket_started`     | `start` entry; `advance` (cook-mode auto-start of next ticket)             | At `start` entry, before orientation. No synthetic emit on mid-ticket resume (hook layer covers it) |
| `red_tdd`            | `start` exit, when ticket is `Red: required`                               | Before directing agent to write the failing test                                                    |
| `green_tdd`          | `start` exit when `Red: skip`; otherwise `post-red` (`Red: required` path) | Before directing agent to implement                                                                 |
| `adversarial_review` | `write-subagent-adversarial-review` gate                                   | Before directing primary agent to write adversarial prompt                                          |
| `open_pr`            | `open-pr` command                                                          | Before `gh pr create`                                                                               |
| `poll_review`        | `poll-review` begins                                                       | Before directing agent to poll                                                                      |
| `record_review`      | `record-review` command                                                    | Before agent records review outcome                                                                 |
| `review_clean`       | Clean review outcome confirmed                                             | On `review_clean_recorded` across all three paths: `record-review`, `poll-review`, `triage-ticket`  |
| `ticket_completed`   | `advance → done` transition                                                | Before/at ticket completion                                                                         |

**Cook mode:** `advance` emits `ticket_completed` then immediately `ticket_started` (next ticket). Last write wins in `gate.json` — `ticket_started` is what the renderer sees. `ticket_completed` gets its full TTL window only in gated mode.

**`subagent_invoked` retired entirely.** The `emitSubagentInvoked` helper and its call site are deleted with `soa-event-feed.ts` — not retained as telemetry. `adversarial_review` (at write-prompt time) replaces its role.

### 3. Gate TTLs — all 3m (v1 baseline)

All 9 gates write `expires_at = now + 3m`. This is a deliberate starting point to observe how hook events bleed through after gate animations. Tune individual gates up based on `state-transitions.log` data after real delivery runs. Values will diverge (e.g., `green_tdd` and `ticket_completed` will likely want longer windows than `open_pr`).

### 4. `codogotchi.enabled` in live `orchestrator.config.json`

Field now present (added during planning). Documents the suppression escape hatch for consumer repos that don't use codogotchi. Default: `true` when absent.

## Explicit Deferrals

- **`advance` gate (stage_advanced):** `closeout-stack.ts` has no existing emit infrastructure; lowest-impact gate (2m TTL concept); deferred until closeout is extended
- **Gate TTL tuning:** all gates ship at 3m; individual TTL adjustment is a post-delivery operational task, not a Phase 17 deliverable
- **`subagentRunner` gate for non-adversarial subagent calls:** `subagent_invoked` retired; no replacement gate in this phase
- **Gate badge UI and `gate.json` renderer integration:** codogotchi Phase 07 scope — Phase 17 ships the writer, Phase 07 ships the consumer
- **File rotation / truncation handling:** `gate.json` is a single-object overwrite, not an append file; rotation is not applicable
- **`CODOGOTCHI_HOME` config field in `orchestrator.config.json`:** env var is the path override; no second override mechanism needed

## Exit Condition

Phase 17 is done when:

1. Running each of the 9 covered delivery commands in a consumer repo with `codogotchi.enabled` (default) causes the correct `gate.json` to appear at `$CODOGOTCHI_HOME/gate.json` — verifiable by `cat` without codogotchi installed.
2. Each written `gate.json` contains valid JSON with `gate` (correct Phase 07 ActivityState name), `since` (current ISO timestamp), and `expires_at` (3 minutes from emit).
3. `adversarial_review` gate fires at the point SoA directs the primary agent to begin writing — confirmed by log timestamp preceding the adversarial prompt artifact write.
4. Running any delivery command with `codogotchi.enabled = false` produces no `gate.json` write and no `~/.codogotchi/` directory creation.
5. No delivery command exits non-zero due to a `gate.json` write failure in any environment (including envs where `~/.codogotchi/` is not writable).
6. `soa-event-feed.ts` is deleted; no `appendSoaEvent` or `emitSubagentInvoked` references remain in the codebase.

## Dependencies

**Codogotchi Phase 07** (consumer — must coordinate gate name contract): gate names written by Phase 17 are the codogotchi Phase 07 schema v4 ActivityState values. Phase 17 ships the writer; Phase 07 ships the renderer that reads `gate.json`.

**Phase 15** (delivered): established the `codogotchi.enabled` config pattern and the `CODOGOTCHI_HOME` env var convention in codogotchi's codebase. Phase 17 inherits both.

## Retrospective

`required` — Phase 17 establishes the durable gate emission architecture for son-of-anton (sidecar model, 9-gate vocabulary, TTL semantics, CODOGOTCHI_HOME path resolution) and retires the Phase 15 NDJSON writer. The 3m TTL baseline is explicitly a starting guess; real delivery data will generate follow-up TTL decisions worth capturing. The `advance` gate deferral and any emit timing surprises should feed forward.
