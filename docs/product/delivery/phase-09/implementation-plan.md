# Phase 09 — Review Loop Hardening

Status: Delivered — ticket stack squash-merged to `main` (PRs [#30](https://github.com/cesarnml/son-of-anton/pull/30), [#31](https://github.com/cesarnml/son-of-anton/pull/31), [#32](https://github.com/cesarnml/son-of-anton/pull/32)); retrospective at [phase-09-review-loop-hardening-retrospective.md](../../retrospectives/phase-09-review-loop-hardening-retrospective.md).

> Closes two quality-gate gaps: vendor billing noise that escalates PRs to `needs_patch`, and a TDD red gate that accepts a "[red]" commit subject without verifying any test actually failed.

## Epic

[docs/product/plans/phase-09-review-pipeline-reliability.md](../../plans/phase-09-review-pipeline-reliability.md)

## Product contract

When this phase is complete:

- A PR whose only external review comments are vendor billing/account-limit messages produces `outcome: "clean"` with no manual intervention.
- An agent cannot pass the `post-red` gate by writing a `[red]` commit subject without running a failing test; the orchestrator verifies the test run exited non-zero before advancing to `red_complete`.
- A branch touching only `.json` files is classified as doc-only and skips `post-red`, subagent review, and PR review gates — consistent with `.md`-only branches today.
- `post-verify` warns (non-blocking) when the working tree has uncommitted changes.
- `bun run ci` is green.

## Grill-Me decisions locked

- **`post-red` enforcement level → hard gate** — `post-verify` throws `WorkflowContractError` if ticket status is `in_progress` and branch is not doc-only. Warn-only would not close the loophole; consistent with how `subagent-review` gates `open-pr`.
- **Billing noise heuristic → bot login + no fenced code block** — body-text matching is fragile (billing copy changes); bot account login is structural. The no-code-block guard handles `coderabbitai`, which also posts walkthroughs — but those are `kind: "summary"` by the fetcher and never reach this pre-filter.
- **`.json` in doc-only → included** — config-only branches (cspell, orchestrator, renovate) should skip code-quality gates. The `&&` guard prevents false positives: a ticket touching `.json` + `.ts` is still classified as code.
- **Red commits for docs tickets → skip via runtime diff, not `Type:` field** — agents can mis-declare `Type: docs` on code tickets; the diff cannot lie.

## Ticket Order

1. `P9.01 Billing Noise Pre-filter`
2. `P9.02 TDD Gate Hardening`
3. `P9.03 Exit Hygiene & Template Fixes`

## Ticket Files

- `ticket-01-billing-noise-filter.md`
- `ticket-02-tdd-gate-hardening.md`
- `ticket-03-exit-hygiene.md`

## Exit Condition

All three tickets merged to main. `bun run ci` green. A replay of the P4.01 triage scenario (Qodo billing comment) produces `clean`, not `needs_patch`. `post-red` on a code ticket without a failing test exits non-zero. A branch touching only `cspell.json` is classified doc-only. Retrospective written.

## CI Baseline

> Baseline recorded: 2026-05-14 — **pass** (0 errors, `bun run ci` exit 0)

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- P9.02 touches `types.ts` and `cli-runner.ts`; P9.03 also touches `cli-runner.ts` — if sequencing shifts, verify no merge conflict on that file.

## Explicit Deferrals

- `post-red` failure attribution (which tests failed, line counts) — only "at least one test failed" is asserted.
- Review artifact atomic commit with `advance` — requires boundary model changes, future phase.
- `.yaml`/`.yml` in `isLocalBranchDocOnly` — same rationale as `.json`, scope creep here.
- Full programmatic subagent review execution — major architectural investment, future phase.
- `reconcile-late-review` finalize-path automation — manual workaround is functional and documented.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- State machine change in P9.02 produces unexpected transitions in existing delivery state fixtures.

## Phase Closeout

Retrospective: required
Why: Phase introduces a new status in the delivery state machine (`red_complete`), a new CLI command (`post-red`), a hard gate in `post-verify`, and a doc-only classification expansion — all durable changes to the orchestrator contract worth documenting.
Trigger: Developer approval of final P9.03 PR merge.
