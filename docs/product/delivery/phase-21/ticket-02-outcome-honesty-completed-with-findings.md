# P21.02 Outcome honesty: completed_with_findings cross-check and terminology pass

Size: 2 points
Type: fix
Scope: subagent-review
Red: required

## Outcome

- `SubagentRunnerOutcome` (`tools/delivery/subagent-runner.ts`) gains `completed_with_findings`; `VALID_OUTCOMES` and ledger validation accept it; `SUBAGENT_LEDGER_SCHEMA_VERSION` bumps to 2 with tolerant reads of v1 rows (codogotchi's existing 240 invocation rows stay valid).
- `decideAdvisoryRunnerOutcome` cross-checks the tag-parsed actionable-findings result from P21.01: runner completed + findings present → `completed_with_findings`; runner completed + literal `None` → `clean`. A `clean` row now guarantees an empty findings block.
- Non-completed termination reasons still collapse to `skipped` exactly as today; the reconcile gate (`reconcile-subagent-review`) semantics are unchanged — it already blocks on findings regardless of label.
- Terminology pass: `docs/template/delivery/adversarial-review-template.md`, `docs/template/delivery/subagent-review-report-template.md`, and `docs/template/delivery/delivery-orchestrator.md` consistently distinguish "runner completed" (finished the review per template) from "review clean" (no actionable findings), and document the new outcome value where ledger outcomes are enumerated.

## Red

- Write failing tests in `tools/delivery/test/`:
  - a completed advisory run whose report's `<actionable-findings>` block lists findings is recorded as `completed_with_findings`, not `clean`;
  - a completed run with literal `None` in the block is recorded as `clean`;
  - a `rate_limit`/`runner_failed` termination still records `skipped` with the original reason;
  - a v1 ledger row (no new outcome, `schemaVersion: 1`) still validates on read.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P21.02): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Thread the P21.01 structured findings result into `decideAdvisoryRunnerOutcome` (and the recorder path in `decideSubagentOutcomeFromRunner` if it can record `clean` for a findings-bearing report); add the enum member and schema bump with the smallest change that passes.

## Refactor

- Align any outcome-enumerating switch statements or docs strings you touched; no opportunistic cleanup beyond them.

## Review Focus

- The honesty invariant: enumerate every code path that can write `outcome: 'clean'` and confirm each one now proves the findings block was empty — a single unexamined path (operator-recorder, triage, fallback) silently re-creates issue #83.
- Schema-version handling: v1 rows must read without warnings; v2 rows must validate the new value.
- The notification ticket (P21.05) will consume this label — confirm the findings count survives to the recorded row or is recoverable from the parse result.
- Intentionally deferred: notification emission (P21.05); any change to reconcile-gate blocking rules (unchanged by design).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
