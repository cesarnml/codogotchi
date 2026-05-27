# Phase 15: Codogotchi Gate Event Emission

**Delivery status:** Delivered. PRs [#56](https://github.com/cesarnml/son-of-anton/pull/56), [#58](https://github.com/cesarnml/son-of-anton/pull/58), [#59](https://github.com/cesarnml/son-of-anton/pull/59), [#60](https://github.com/cesarnml/son-of-anton/pull/60), [#61](https://github.com/cesarnml/son-of-anton/pull/61), [#62](https://github.com/cesarnml/son-of-anton/pull/62) — stacked, pending closeout-stack merge. Codogotchi alignment cross-repo draft: [`notes/public/codogotchi-alignment-draft.md`](../../../../notes/public/codogotchi-alignment-draft.md). Retrospective: [`docs/product/retrospectives/phase-15-codogotchi-gate-event-emission-retrospective.md`](../../retrospectives/phase-15-codogotchi-gate-event-emission-retrospective.md).

## TL;DR

**Goal:** Connect the unconnected wire — SoA has never written to `.soa/events.ndjson` despite the codogotchi hook binary being built to consume it. This phase adds the writer.

**Ships:**

- `tools/delivery/soa-event-feed.ts` — the NDJSON append writer module
- Emit calls at five recognized gate points: `ticket_started`, `ticket_completed`, `pr_review_window_opened`, `review_clean_recorded`, `subagent_invoked`
- `review_clean_recorded` covered on all three paths: `record-review`, `poll-review`, and `triage-ticket` (when outcome is `clean`)
- `orchestrator.config.json` gains a `codogotchi` config field (`enabled` by default) to gate all event emission
- `AGENTS.soa.md` documents `.soa/` as a local-only sidecar and references the gitignore recommendation
- `notes/public/codogotchi-alignment-draft.md` — a cross-repo draft plan scoping what codogotchi needs to do to verify alignment with the new emit path

**Defers:** `verification_failed`, `risky_diff_detected`, `flow_state_entered`, `stage_advanced` — all four deferred events from the original contract, plus file rotation and cross-repo fan-out.

---

Codogotchi's Mali pet changes animation state based on what the AI agent is doing. The hook binary that drives it reads `.soa/events.ndjson` to obtain explicit orchestrator gate signals — but SoA has never written to that file. The contract doc in the codogotchi repo (`docs/contracts/soa-event-feed.md`) correctly declares SoA as the producer; the hook is already wired to consume it. The wire is unconnected at the SoA end.

Right now the hook falls back entirely to Claude/Codex tool-call heuristics. Mali never enters `hyped`, `celebrating`, `waiting`, `calling_for_backup`, or any other orchestrator-specific state because SoA never emits a signal. This phase adds the writer so those states become reachable.

## Phase Goal

This phase should leave the product in a state where:

- Running `bun run deliver start P15.01` in a consumer repo with codogotchi enabled causes `.soa/events.ndjson` to gain a `ticket_started` line within the same command invocation.
- Running `bun run deliver advance` when a ticket transitions to `done` produces a `ticket_completed` line.
- Running `bun run deliver open-pr` appends `pr_review_window_opened` when the review window is real (i.e., `buildReviewWindowReadyEvent` returns non-undefined — not on `pr_opened`).
- Recording or polling a clean review appends `review_clean_recorded`. This covers all three paths: `record-review`, `poll-review`, and `triage-ticket` when the reconciled outcome is `clean`.
- Invoking a subagent appends `subagent_invoked`. Emit fires in `cli-runner.ts` immediately before the `spawnSync` call (~line 907), using `worktreePath` as the project root.
- No delivery command aborts due to an event-feed write failure — all emits are best-effort (`try/catch`, silent on error).
- Setting `codogotchi.enabled = false` in `orchestrator.config.json` suppresses all event writes. Default is `enabled`.
- `.soa/events.ndjson` is documented in `AGENTS.soa.md` as a local-only sidecar and listed in the gitignore example.

## Committed Scope

### 1. SoA event feed writer (`tools/delivery/soa-event-feed.ts`)

New module: `appendSoaEvent(projectRoot, event)` appends one NDJSON line to `${projectRoot}/.soa/events.ndjson`, creating the directory if absent. `buildSoaEventLine(name, opts?)` constructs the event object with `ts: new Date().toISOString()`. No external deps; no Zod on the write path (we construct; the consumer validates on read).

### 2. Five emit points

Emit calls added at recognized gate boundaries, all best-effort:

| Event                     | Emit site                                                                     | Trigger                                                             |
| ------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `ticket_started`          | `cli-runner.ts` — `start` command and `advance` on `→ in_progress` transition | After state transition succeeds                                     |
| `ticket_completed`        | `cli-runner.ts` — `advance` on `→ done` transition                            | After state transition succeeds                                     |
| `pr_review_window_opened` | `cli-runner.ts` — `open-pr` command                                           | When `buildReviewWindowReadyEvent` returns non-undefined            |
| `review_clean_recorded`   | `cli-runner.ts` — `record-review`, `poll-review`, and `triage-ticket` paths   | When resolved outcome is `clean`                                    |
| `subagent_invoked`        | `cli-runner.ts` — immediately before `spawnSync` at ~line 907                 | Before runner subprocess is spawned; `payload` carries `runnerKind` |

`projectRoot` sourcing: `process.cwd()` for all `cli-runner.ts` emit points except `subagent_invoked`, which uses `worktreePath` (already available at the spawn site).

### 3. `orchestrator.config.json` codogotchi gate

A new optional `codogotchi` field: `{ enabled: boolean }`. Default when absent: `enabled`. All emit calls check this gate before writing. Consumer repos that don't use codogotchi may set `enabled: false` to suppress sidecar file creation.

### 4. `AGENTS.soa.md` and gitignore documentation

One-paragraph note explaining `.soa/` is a local-only sidecar directory for codogotchi event signals. Add `.soa/` to the gitignore example. Reference the codogotchi contract doc for the full schema.

### 5. Cross-repo alignment draft plan

Write `notes/public/codogotchi-alignment-draft.md` — a full-audit draft plan scoping the codogotchi-side work needed to verify alignment with the new SoA emit path. See [Codogotchi Alignment Draft](#codogotchi-alignment-draft) below for scope.

## Explicit Deferrals

- **`verification_failed`**: Requires detecting when `bun run verify` exits non-zero inside an orchestrated step. SoA does not currently capture the verify exit code as a structured event. Deferred until the verify gate is formalized as a first-class orchestrator step.
- **`risky_diff_detected`**: Requires diff size / risk heuristics. Undefined trigger. Deferred.
- **`flow_state_entered`**: No current orchestrator model of "flow state." Deferred.
- **`stage_advanced`**: No current stage-advance command or concept in SoA. Deferred.
- **File rotation / truncation**: Codogotchi's consumer handles inode mismatch and resets the read offset. SoA just appends; rotation is not its problem.
- **Cross-repo fan-out**: One events file per project root, per the contract. No multi-root broadcasting.
- **Live codogotchi integration test as exit condition**: Phase 15 exit is scoped to SOA's write path (correct lines, valid schema). End-to-end animation verification belongs in a codogotchi-side phase.

## Exit Condition

Phase 15 is done when:

1. Running each covered delivery command in a consumer repo with `codogotchi.enabled` (default) causes the correct NDJSON line to appear in `.soa/events.ndjson` — verifiable by `cat` or `tail` without requiring codogotchi to be installed.
2. Each emitted line parses as valid JSON, contains `name`, `ts`, and (where applicable) `plan_key` / `ticket_id` fields matching the codogotchi schema.
3. Running the same commands with `codogotchi.enabled = false` produces no `.soa/` directory and no events file.
4. No delivery command exits non-zero due to an event-feed write failure in any environment (including envs where `.soa/` is not writable — the try/catch absorbs it).
5. `notes/public/codogotchi-alignment-draft.md` is written and committed.

## Retrospective

`required` — This phase establishes the durable integration boundary between two repos. The emit pattern, config gate, and file format chosen here are the baseline all deferred events will inherit. A retrospective captures what held and what the deferred events will need, directly feeding codogotchi Phase 2 planning.
