# Phase 7 - Runtime Delivery Policy Overrides for Execute/Resume

> Add bounded runtime delivery-policy overrides with persisted run-level policy state so execute/resume can change operational behavior without config churn in `main`.

## Epic

[Phase 7 product plan](/Users/cesar/code/son-of-anton/docs/product/plans/phase-07-runtime-delivery-policy-overrides.md)

## Product contract

Developers can start and resume orchestrated delivery runs with explicit runtime policy overrides for boundary mode, internal/external review policy, and review-subagent selection. The resolved run policy persists in `state.json`, resume refuses silent policy drift on the bounded Phase 07 surface, and operator-facing output makes the governing run policy visible.

## Grill-Me decisions locked

- Persist run policy as a dedicated top-level `runPolicy` object in `state.json` -> keeps run-level policy separate from ticket progress and enables direct divergence comparison.
- Persist review-subagent selection as an explicit tagged shape -> distinguishes same-type fallback from concrete override without relying on omission semantics.
- Divergence detection for resume compares only the bounded Phase 07 policy surface -> matches approved scope and avoids broad config-drift blocking.
- Delivery engine owns parsing, persistence, and resume guardrails -> keeps the state machine and policy semantics in one testable runtime boundary.
- Operator syntax uses explicit flags, not presets or sentinel values -> yields clearer validation, refusal messages, and recovery commands.
- Ticket stack includes a final docs/retrospective slice -> keeps operator guidance and phase closeout separate from state-machine changes.

## Ticket Order

1. `P7.01 Run-policy state model and migration`
2. `P7.02 Runtime override parsing and execute-time resolution`
3. `P7.03 Resume divergence guardrails and baseline selection`
4. `P7.04 Run-policy observability in status and workflow output`
5. `P7.05 Docs updates and retrospective`

## Ticket Files

- `ticket-01-run-policy-state-model-and-migration.md`
- `ticket-02-runtime-override-parsing-and-execute-time-resolution.md`
- `ticket-03-resume-divergence-guardrails-and-baseline-selection.md`
- `ticket-04-run-policy-observability-in-status-and-workflow-output.md`
- `ticket-05-docs-updates-and-retrospective.md`

## Exit Condition

Starting a run can patch repo-default delivery policy with explicit runtime flags, the resolved policy is persisted as top-level run state, and resuming a run refuses silent divergence until the operator explicitly selects `--baseline=orchestrator` or `--baseline=run-policy` and optionally applies additional overrides. Status and resume-facing output show the active run policy clearly enough for a second operator to understand the governing rules without reading code or editing config files.

## CI Baseline

Run `bun run ci:quiet` on `main` before the first ticket starts and record the result here. This snapshot makes per-ticket CI diffs unambiguous.

> Baseline recorded: [date] - [pass / N pre-existing errors: brief summary]

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- `P7.03` must not ship until `P7.01` and `P7.02` have landed because resume guardrails depend on persisted run-policy state and execute-time resolution semantics.
- `P7.05` should verify the final operator-facing command examples against shipped flags and refusal text rather than draft command shapes.

## Explicit Deferrals

- Named policy presets or profiles.
- Runtime override of unrelated orchestrator config keys.
- Per-ticket run-policy history or snapshots.
- Standalone `ai-review` parity for the Phase 07 policy model.
- Automatic mutation or reconciliation of `orchestrator.config.json`.

## Stop Conditions

- Existing orchestrator state files reveal incompatible persistence assumptions that cannot be normalized safely within ticket scope.
- Resume precedence or baseline semantics remain ambiguous after implementation-level validation.
- Broken CI that cannot be resolved within the current ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: This phase changes execute/resume operator workflow semantics and introduces a durable run-policy boundary with likely follow-up learning.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-07-runtime-delivery-policy-overrides-retrospective.md`
