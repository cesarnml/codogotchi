# P20.01 Config, types, template, refactor-suggestions parser & reconciliation

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- `orchestrator.config.json` accepts `reviewPolicy.refactorReview: "disabled" | "runner_on_red"`; any other value (including `runner_on_red_strict`) is rejected at config load with a clear error, matching how other `reviewPolicy` fields are validated.
- New ticket-state fields exist in `types.ts` for tracking the refactor-review prompt path, outcome, and reviewed-head SHA — named to mirror the existing adversarial fields (e.g. `subagentAdversarialPromptPath` → `refactorReviewPromptPath`) without colliding with them.
- `docs/template/delivery/refactor-review-template.md` exists: local-quality-signal brief (duplication, naming, dead code, complexity, test-name/behavior alignment — explicitly not architecture or invariant/attack-surface hunting) plus a literal copy-me `<refactor-suggestions>` tag skeleton per `notes/public/subagent-report-parser-contract.md`.
- A new tag-based parser extracts the `<refactor-suggestions>` block from a refactor-review report: bullets between the tags, or the literal `None` for a clean report. This is a **new, separate** function from the adversarial gate's `extractReportSection`/`CANONICAL_REPORT_SECTION_HEADINGS` — it does not touch or reuse that heading-based machinery.
- Refactor-review ledger reconciliation logic exists (analog of `reconcileReview`'s Condition A/B in `reconciliation.ts`): detects `[refactor-review]`-labeled commits since the row's `reviewedHeadSha`, and blocks when reviewed paths changed without a labeled commit or `deferred` row, or when the report lists suggestions but no qualifying patch/deferred row exists.
- Ledger row shape supports `id` (`R1`, `R2`, …), `summary`, `decision` (`accepted`/`rejected`/`deferred`), `reason` (required for reject/defer).

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value.**
- Write a failing test asserting `orchestrator.config.json` rejects an invalid `refactorReview` value (e.g. `"runner_on_red_strict"` or an arbitrary string) at config load.
- Write a failing test asserting a valid `refactorReview: "runner_on_red"` config loads and resolves correctly.
- Write failing tests for the `<refactor-suggestions>` tag parser: tagged block with bullets parses correctly; literal `None` → clean-empty, no warning; missing close tag → parses to EOF; content present but tag missing/misnamed → 0-parse.
- Write failing tests for refactor-review reconciliation: unlabeled commit touching reviewed paths with no deferred row → blocked; report lists suggestions with no patch/deferred row → blocked; labeled `[refactor-review]` commit touching reviewed paths → clean; `deferred` row present → clean.
- Run the test suite and confirm all new tests fail before implementation exists.
- Commit with suffix `[red]`: `test(P20.01): cover refactor-review config, parser, and reconciliation [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Extend `reviewPolicy` validation (wherever `subagentReview`/`prReview` are currently validated) to accept the new `refactorReview` field with its two-value enum.
- Add the new ticket-state fields to `types.ts`.
- Write `docs/template/delivery/refactor-review-template.md`.
- Add the tag parser and reconciliation logic as new, clearly-named functions — do not modify `parseAdvisoryObservations`, `extractReportSection`, `CANONICAL_REPORT_SECTION_HEADINGS`, or `parseActionableFindings` in `reconciliation.ts`. Prefer a new module (e.g. `tools/delivery/refactor-review.ts`) over inserting refactor-specific branches into the existing adversarial-review functions, so the two gates' parsing logic stays fully independent.
- Implement the smallest code that makes the new tests pass.

## Refactor

- Reuse `SubagentRunnerArtifact`/`SubagentRunnerInvocation` types from `subagent-runner.ts` for the refactor-review ledger shape rather than inventing a parallel artifact type, since that shape is already generic (not adversarial-specific).
- Keep the new module's public surface minimal — export only what ticket 20.02's CLI commands will need.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Confirm the new tag parser does not import from or modify the adversarial gate's heading-based extraction — verify by diff, not just by reading the new file.
- Confirm `runner_on_red_strict` is rejected by config validation, not silently accepted and ignored.
- Confirm reconciliation Condition A/B logic mirrors the adversarial analog's intent (silent-lie prevention) without literally duplicating its adversarial-specific constants (e.g. the `[subagent-review]` subject pattern must not be reused for `[refactor-review]` detection).
- Public API shape of the new module — will ticket 20.02 be able to call it cleanly.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
