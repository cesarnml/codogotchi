# Phase 12 — Gate placement refactor

> Move the `post-red` gate to before implementation, add a `Red:` ticket-metadata field so no-testable-behavior tickets can declare the skip honestly, and delete the `--red-commit-sha <sha>` lie-enabling flag.

## Epic

Product plan: [`docs/product/plans/phase-12-gate-placement-refactor.md`](../../plans/phase-12-gate-placement-refactor.md) (committed `cbab0e0`).

## Product contract

When phase-12 is done, a delivery agent reading the documented critical order encounters the TDD discipline check _before_ implementation, not after. Tickets with no testable behavior (scaffolding, ops, deploy) declare `Red: skip` in their metadata block and the orchestrator honors it without operator intervention. The `--red-commit-sha <sha>` flag — which let operators record the green commit as the red commit and persisted that lie into `state.json` — is gone. The two honest paths through `post-red` are: author a `[red]` commit before continuing, or declare `Red: skip` in the ticket metadata.

## Grill-Me decisions locked

- **Ticket shape: 2 stacked PRs (Shape C).** All code in T1; all docs + retro in T2. Phase is small enough (~200 LOC code + ~100 LOC docs) that splitting parser/gate-skip/bypass-deletion into separate PRs is ceremony without real risk reduction.
- **`Red:` parsing happens at `start`.** Parser lifts the value into `state.json` as `redPolicy: 'required' | 'skip'` on the ticket state record. Gate code reads from state, does not re-parse markdown.
- **Strict-reject on unrecognized values.** Exact lowercase match on `required` | `skip`. Anything else throws at `start` with an explicit error naming the two valid literals.
- **Skip precedence: OR.** `runPostRed` skips when `redPolicy === 'skip'` OR `isLocalBranchDocOnly` returns true. Log message identifies which signal(s) triggered. Doc-only auto-skip is structural; `Red: skip` is declarative; either is sufficient grounds to skip.
- **TDD discipline within T1: single `[red]` commit on the parser test.** The orchestrator's `post-red` only inspects the first `[red]` commit; subsequent green-side work (gate-skip honoring, flag deletion, error-text update) lands as iterative commits without additional `[red]` ceremony.
- **Phase-12 own tickets declare `Red:` from day one.** T1: `Red: required`. T2: `Red: skip`. Defaults absorb pre-T1 behavior; declaring the field eats own dogfood.
- **No single-commit TDD support.** No `TDD:` field. No diff-revert verification. Deferred from product plan; delivery does not resurrect it.

## Ticket Order

1. `P12.01 Add Red metadata field and delete --red-commit-sha`
2. `P12.02 Gate placement refactor docs and retrospective`

## Ticket Files

- `ticket-01-add-red-metadata-and-delete-red-commit-sha.md`
- `ticket-02-gate-placement-docs-and-retrospective.md`

## Exit Condition

`bun run ci:quiet` is green on the final tip of the stacked PR chain. The `Red:` field is parsed and honored by the orchestrator. The `--red-commit-sha` flag is gone from CLI parsing, error text, and all documentation. `docs/template/delivery/delivery-orchestrator.md`, `docs/template/overview/start-here.md`, `docs/template/delivery/tdd-workflow.md`, `docs/template/stubs/ticket.template.md`, and the `son-of-anton-ethos` skill all describe the new critical order with `post-red` between `commit [red]` and `implement + verify`. The phase-12 retrospective is written at `docs/product/retrospectives/phase-12-gate-placement-refactor-retrospective.md`.

## CI Baseline

> Baseline recorded: 2026-05-20 on `cbab0e0` — pass (434 tests, 0 fail, 815 expect() calls, 2.48s via `bun run ci:quiet`).

## Review Rules

- Tickets must be merged in order. T2 is base-stacked onto T1's branch.
- Each ticket PR must pass `bun run ci:quiet` before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- **External AI PR review is disabled** (`reviewPolicy.prReview: "disabled"` in `orchestrator.config.json`). `poll-review` will auto-record `clean` on both PRs without a wait window.
- **Subagent review is the only external-AI pre-merge gate for T1.** Phase-11's broadened adversarial-review template carries the load. T1's subagent invocation must use the filled template at `docs/template/delivery/adversarial-review-template.md` and probe the diff-derived attack surfaces named there.
- T2 is doc-only; `subagent-review` auto-skips under `skip_doc_only`. Human review only.
- Both PRs use Conventional-Commit-style title + ticket suffix (`feat(delivery): ... [P12.01]`, `docs(phase-12): ... [P12.02]`).

## Explicit Deferrals

- **Single-commit TDD support.** No `TDD: single-commit` field. No diff-revert verification. The reorder makes the case impossible under protocol-following work; shipping the convention would resurrect `--red-commit-sha`'s attractive-nuisance properties under a new name.
- **Runner-artifact schema changes.** Phase-11 work; phase-12 does not touch it.
- **Phase-13 hygiene work** (M9 Biome reformat, M10 resume-prompt persistence, M11 baseline persistence, M12 positional-arg parsing, M13 poll-review `skipped` detection, M14 worktree refresh on `advance`).
- **`verify-red` standalone CLI subcommand.** Verification work lives inside `post-red`.
- **State.json archaeology / migration tooling.** Past records are the historical record; phase-12 makes future records honest.
- **Adversarial review template re-litigation.** Phase-11 work.
- **`[red]` commit authoring tooling** (commit hooks, lint rules, auto-prefix). Phase-12 is gate ordering only.
- **Bundled "while we're here" doc edits beyond the five named surfaces** (`delivery-orchestrator.md`, `start-here.md`, `tdd-workflow.md`, `ticket.template.md`, `son-of-anton-ethos`). If other docs surface cross-references during T2, surface them as a stop condition, not silent expansion.
- **Structured triage `findingDecisions` schema and template Rev 13.** Future phase.

## Stop Conditions

- **Bypass references in >5 test files.** If T1 discovers that `--red-commit-sha` or `redCommitSha` (when used as a CLI-flag-supplied value, not the legitimate state field) is referenced in more than ~5 test files across `tools/delivery/test/`, pause and surface the list. The ticket scope may need to shrink, or the agent should ask whether to bundle the cleanup or split it.
- **Subagent-review surfaces a parser/gate-skip design finding.** If the subagent flags an issue with parser strictness, error-message wording, or skip-precedence semantics (the OR rule), that is a design-level finding. Surface it for developer judgment rather than auto-patching. The decompose grill is the design contract; deviating requires explicit re-approval.
- **Doc cross-references beyond the five named surfaces.** If T2 discovers that other docs (READMEs, retrospectives, contract docs) reference the old gate ordering, pause and surface the list. Don't silently expand T2's scope; either bundle them deliberately or defer to standalone follow-ups.
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: phase-12 changes the orchestrator's documented critical order (operator workflow change), introduces a new ticket-metadata field that consumers adopt (durable boundary), and deletes a previously-supported CLI flag (durable boundary). These warrant a recorded retrospective so downstream phases inherit the rationale, not just the result.
Trigger: developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-12-gate-placement-refactor-retrospective.md`
