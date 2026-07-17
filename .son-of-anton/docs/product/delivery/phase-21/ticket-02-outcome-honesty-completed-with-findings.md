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

Red first: `tools/delivery/test/p21-02.test.ts` — `decideAdvisoryRunnerOutcome` recorded `clean` for a completed run whose report listed actionable findings; the new v2 ledger-row validation test also failed until `completed_with_findings` joined `VALID_OUTCOMES`.
Why this path: threaded an optional `actionableFindings?: ActionableFindingsParseResult` param into `decideAdvisoryRunnerOutcome` (programmatic-runner path) and `decideSubagentOutcomeFromRunner` (deprecated recorder path), gated behind a shared `hasHonestFindings` helper (found + closed + not-explicit-`None` + non-empty). The one call site with a report to cross-check (`cli-runner.ts`'s adversarial `subagent-review` runner invocation) now parses `<actionable-findings>` from `result.stdout ?? result.rawOutput` before deciding the outcome; the refactor-review gate's `runProgrammaticSubagentReview` call site is untouched (different tag, different domain) and keeps recording `clean` because it never supplies `actionableFindings`.
Alternative considered: computing the cross-check inside `runProgrammaticSubagentReview`/`decideAdvisoryRunnerOutcome` unconditionally by parsing report text internally — rejected because the refactor-review call site's report uses a different tag (`<refactor-suggestions>`) and a different suggestion-acceptance model; forcing the actionable-findings parser onto it would misclassify refactor-only reports.
Deferred: notification emission on `completed_with_findings` (P21.05); any change to `reconcile-subagent-review` blocking rules (unchanged by design — it already blocks on findings regardless of label).
Contract note: none — ticket metadata (`Type: fix`, `Scope: subagent-review`) matched the change as delivered.

Refactor-review adjudication (cursor-cli, clean report, 3 suggestions): accepted hoisting the single `parseActionableFindings` call in `cli-runner.ts` so the decide-time parse and the zero-parse loud-floor check reuse one result instead of re-parsing the same report text; accepted adding direct test coverage for `decideSubagentOutcomeFromRunner`'s findings-cross-check branch (previously only reachable via the deprecated function's own logic, untested). Rejected consolidating `hasHonestFindings` with `reconciliation.ts`'s `isSuspiciousActionableFindingsParse` into one shared exported predicate — the two answer different questions (parse-health/drift-warning vs. semantic clean-or-not) and merging them would cross `reconciliation.ts`'s parser-contract module boundary beyond this ticket's 2-point scope.
