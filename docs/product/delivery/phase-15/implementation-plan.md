# Phase 15 — Codogotchi Gate Event Emission

> Connect the unconnected wire: add the SoA-side writer that appends NDJSON lines to `.soa/events.ndjson` at recognized gate points so the codogotchi hook binary can finally pick up explicit orchestrator signals.

## Epic

Standalone phase. Source product plan: [`docs/product/plans/phase-15-codogotchi-gate-event-emission.md`](../../plans/phase-15-codogotchi-gate-event-emission.md). Codogotchi alignment cross-repo draft: [`notes/public/codogotchi-alignment-draft.md`](../../../../notes/public/codogotchi-alignment-draft.md). Retrospective: [`docs/product/retrospectives/phase-15-codogotchi-gate-event-emission-retrospective.md`](../../retrospectives/phase-15-codogotchi-gate-event-emission-retrospective.md).

## Product contract

After Phase 15 ships, running any of these delivery commands in a consumer repo with `codogotchi.enabled` (default) appends the correct event line to `.soa/events.ndjson` within the same command invocation:

- `deliver start <ticket>` → `ticket_started`
- `deliver advance` (transition to `in_progress`) → `ticket_started`
- `deliver advance` (transition to `done`) → `ticket_completed`
- `deliver open-pr` (review window real) → `pr_review_window_opened`
- `deliver record-review` / `poll-review` / `triage-ticket` (outcome=clean) → `review_clean_recorded`
- Subagent spawn → `subagent_invoked`

All emits are best-effort: a write failure never aborts a delivery command. Setting `codogotchi.enabled: false` in `orchestrator.config.json` suppresses all writes — no `.soa/` directory is created.

## Grill-Me decisions locked

| Decision                                                                                                     | Rationale                                                                                                        |
| ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `subagent_invoked` emits in `cli-runner.ts` (not `subagent-runner.ts`), using `worktreePath` as project root | Spawn site lives in `cli-runner.ts` ~line 907; `subagent-runner.ts` is a pure utilities module with no I/O       |
| `review_clean_recorded` emits on all three paths (`record-review`, `poll-review`, `triage-ticket`)           | A late clean review is semantically identical to a direct clean record; skipping triage path creates a dead spot |
| Exit scoped to SoA write-path verification only                                                              | End-to-end animation verification belongs in a codogotchi-side phase, not Phase 15                               |
| `orchestrator.config.json` gains `codogotchi: { enabled: boolean }`, default enabled                         | Operator escape hatch; opt-out default preserves happy path for existing users                                   |
| Writer module + config gate land together in P15.01                                                          | Foundation must be atomic — writer is meaningless without the gate it consults                                   |
| All three `review_clean_recorded` paths in one ticket (P15.04)                                               | Parallel code; splitting triples ceremony for negligible incremental value                                       |
| Dedicated final docs ticket (P15.06)                                                                         | Clean separation; correct `skip_doc_only` subagent-review flow; retrospective slot                               |
| Filesystem-level integration tests against tmp dirs                                                          | Proves the actual contract codogotchi consumes; matches existing `pN-NN.test.ts` pattern                         |
| No dedicated e2e smoke ticket                                                                                | Per-ticket coverage is sufficient; no realistic inter-command propagation bug surface                            |
| Strict linear stack                                                                                          | Cleaner orchestrator state machine; simpler `closeout-stack`                                                     |
| `orchestrator.config.json` in this repo untouched                                                            | Respects default-enabled semantics; avoids implying the field is required                                        |

## Ticket Order

1. `P15.01 Add soa-event-feed.ts writer + codogotchi.enabled config gate`
2. `P15.02 Emit ticket_started + ticket_completed`
3. `P15.03 Emit pr_review_window_opened`
4. `P15.04 Emit review_clean_recorded across record/poll/triage paths`
5. `P15.05 Emit subagent_invoked at runner pre-spawn`
6. `P15.06 Phase 15 docs + retrospective`

## Ticket Files

- `ticket-01-soa-event-feed-writer-and-codogotchi-config-gate.md`
- `ticket-02-emit-ticket-started-and-ticket-completed.md`
- `ticket-03-emit-pr-review-window-opened.md`
- `ticket-04-emit-review-clean-recorded.md`
- `ticket-05-emit-subagent-invoked.md`
- `ticket-06-phase-15-docs-and-retrospective.md`

## Exit Condition

Phase 15 is done when running the SoA delivery commands in a consumer repo with `codogotchi.enabled` produces the correct NDJSON lines in `.soa/events.ndjson`, each line parses as valid JSON matching the codogotchi schema, all delivery commands exit zero even when the write would fail, setting `codogotchi.enabled: false` produces no `.soa/` directory, and the codogotchi alignment cross-repo draft is committed under `notes/public/`.

## CI Baseline

## Review Rules

- Tickets must be merged in order (strict linear stack).
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Subagent review policy follows repo default (`skip_doc_only`); P15.06 docs ticket auto-skips subagent review.

## Explicit Deferrals

- `verification_failed`, `risky_diff_detected`, `flow_state_entered`, `stage_advanced` — all four contract events with no current SoA-side gate point.
- File rotation / truncation handling on the SoA side (codogotchi consumer handles inode reset).
- Cross-repo fan-out (one events file per project root).
- Live codogotchi end-to-end animation verification (belongs in a codogotchi-side phase, scoped by the cross-repo draft).

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Discovery that an emit site has no clean integration test path (would block Red discipline).
- Discovery that the codogotchi contract document is not actually current after all (would force a contract negotiation).
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: This phase establishes the durable integration boundary between SoA and codogotchi. The emit pattern, config gate, and file format chosen here are the baseline all four deferred events will inherit. A retrospective captures what held, what didn't, and what the deferred events will need — directly feeding codogotchi Phase 2 planning.
Trigger: Developer approval of P15.06 final PR merge.
Artifact: `docs/product/retrospectives/phase-15-codogotchi-gate-event-emission-retrospective.md`
