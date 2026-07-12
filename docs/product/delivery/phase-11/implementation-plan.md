# Phase 11 Implementation Plan

Source product plan: [`docs/product/plans/phase-11-subagent-review-class-absorption-and-artifact-honesty.md`](../../plans/phase-11-subagent-review-class-absorption-and-artifact-honesty.md).

## Phase goal recap

Make `subagent-review` absorb the bulk of CodeRabbit's diff-derived finding classes and produce honest, auditable persisted artifacts so external CR becomes an occasional confirmation gate. Ship across two surfaces: the adversarial review template (docs) and the CLI / artifact / ethos contract (code + docs).

## Sequencing constraint

Risk #4 of the product plan ("SoA-delivering-itself recursion") dictates hard ordering: **artifact-schema work lands and stabilizes before the CLI runner-contract change**. A buggy mid-phase artifact schema poisons in-flight tickets that depend on it.

```
P11.01 (artifact schema + adapter) ──► P11.03 (recorder + idempotency) ──► P11.04 (termination honesty) ──► P11.05 (phase exit)
P11.02 (template + ethos docs) ──── parallel ───────────────────────────────────────────────────────────────────────────────►
```

P11.02 is docs-only and can land in parallel with any code ticket.

## Ticket Order

1. `P11.01 Structured SubagentRunnerArtifact schema with forward-compat adapter`
2. `P11.02 Adversarial template expansion and ethos advisory-runner correction`
3. `P11.03 subagent-review recorder mode and artifact-existence-at-HEAD idempotency`
4. `P11.04 subagent-review termination honesty`
5. `P11.05 Phase exit and retrospective`

## Ticket Files

- `ticket-01-structured-subagent-runner-artifact-schema-and-adapter.md`
- `ticket-02-adversarial-template-expansion-and-ethos-correction.md`
- `ticket-03-subagent-review-recorder-mode-and-head-idempotency.md`
- `ticket-04-subagent-review-termination-honesty.md`
- `ticket-05-phase-exit-and-retrospective.md`

## Exit Condition

Phase-11 closes when every item in the product plan's "Exit Condition" section is demonstrably true and `bun run ci` is green on the final stacked merge. P11.05 writes the retrospective per the `soa-write-retrospective` skill.

## Ticket Index

| #                                                                             | Title                                                                                                         | Type  | Size | Blocks | Blocked by                     |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ----- | ---- | ------ | ------------------------------ |
| [P11.01](ticket-01-structured-subagent-runner-artifact-schema-and-adapter.md) | Structured `SubagentRunnerArtifact` schema with forward-compat adapter                                        | feat  | 3    | P11.03 | —                              |
| [P11.02](ticket-02-adversarial-template-expansion-and-ethos-correction.md)    | Adversarial template expansion + ethos advisory-runner correction                                             | docs  | 3    | —      | —                              |
| [P11.03](ticket-03-subagent-review-recorder-mode-and-head-idempotency.md)     | `subagent-review` recorder mode + artifact-existence-at-HEAD idempotency                                      | feat  | 3    | P11.04 | P11.01                         |
| [P11.04](ticket-04-subagent-review-termination-honesty.md)                    | `subagent-review` termination honesty (subprocess wait, `terminatedReason` gating, constrained auto-fallback) | fix   | 3    | P11.05 | P11.03                         |
| [P11.05](ticket-05-phase-exit-and-retrospective.md)                           | Phase exit + retrospective                                                                                    | chore | 1    | —      | P11.01, P11.02, P11.03, P11.04 |

## Cross-cutting test strategy

- P11.01 introduces a `tests/fixtures/legacy-subagent-runner/` directory seeded with copies of real codogotchi phase-01 4-field artifacts (sanitized of any in-repo paths if needed). The forward-compat adapter is tested against these on-disk fixtures so the adapter is proven against actual shapes consumers will hand it.
- P11.03 and P11.04 reuse the structured artifact type from P11.01 — no test fixtures of their own beyond what the CLI tests already provide.
- All tickets follow red-then-green except P11.02 and P11.05, which are docs-only (no Red step per the canonical template).

## Patch-plan cross-reference

Patch IDs (`[M1]`, `[Rev 12]`, etc.) referenced in the product plan map onto tickets as follows:

- **P11.01:** M5, schema-adapter (Q5 resolution)
- **P11.02:** M1, M2, Rev 12, Rev 15, M15
- **P11.03:** M3 (code-read-corrected), M4
- **P11.04:** M6, M8, M3/M6-refined auto-fallback constraint
