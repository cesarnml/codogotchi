# P8.02 Docs updates and retrospective

Size: 1 point
Type: docs
Scope: docs

## Outcome

- `docs/template/overview/start-here.md` and `docs/template/delivery/delivery-orchestrator.md` accurately reflect that `--baseline run-policy` now governs execution (not just state persistence).
- `README.md` checked — no changes required if the fix is internal and no user-visible command surface changed.
- Required Phase 08 retrospective written at `docs/product/retrospectives/phase-08-runpolicy-consumer-wiring-retrospective.md` using the `soa-write-retrospective` skill.

## Red

- Add a doc-surface test in `p8-01.test.ts` (or a new `p8-02.test.ts`) that reads `start-here.md` and `delivery-orchestrator.md` via `readFileSync` and asserts each contains `--baseline run-policy` with accurate description — test fails if either file is missing the wording or contradicts the shipped behavior.
- Run `bun run verify:quiet` and confirm the test fails before doc edits.
- Commit: `test(P8.02): doc-surface tests for baseline run-policy correctness [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Update `start-here.md` and `delivery-orchestrator.md` if they describe `--baseline run-policy` in a way that implies it only affects state (not execution). Correct to: it governs execution for the current process invocation.
- Write the retrospective once P8.01 is merged — use the `soa-write-retrospective` skill at `.agents/skills/write-retrospective/SKILL.md`.
- Retrospective path: `docs/product/retrospectives/phase-08-runpolicy-consumer-wiring-retrospective.md`

## Refactor

- Remove or correct any wording in docs that describes the runPolicy feature as "persisted but not yet applied to execution."
- Limit edits to docs and retrospective artifacts — no code changes.

## Review Focus

- Whether docs describe `--baseline run-policy` behavior accurately end-to-end: divergence detected → baseline resolved → persisted runPolicy governs this run.
- Whether the retrospective captures the durable process lesson (don't ship policy persistence without wiring consumption in the same phase) rather than restating the changelog.
- `README.md` — confirm no user-visible command surface changed that requires a README update.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: doc-surface test checking `delivery-orchestrator.md` contains accurate `--baseline run-policy` description
Why this path: same pattern as P7.05 — `readFileSync` + `toContain` assertions prove docs were updated without snapshot maintenance burden
Alternative considered: folding docs into P8.01 — rejected because it mixes a correctness fix with doc authoring in one PR, making the diff harder to review
Deferred: README flag surface documentation (internal correctness fix; no new user-visible commands)
