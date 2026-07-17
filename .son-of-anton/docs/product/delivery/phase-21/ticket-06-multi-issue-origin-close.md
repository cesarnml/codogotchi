# P21.06 Multi-issue Origin close

Size: 2 points
Type: feat
Scope: delivery
Red: required

## Outcome

- `parseOriginIssueNumber` (`tools/delivery/planning.ts`) is superseded by a multi-line-aware parser that returns every `Origin issue: #<N>` line from the `## Epic` section, in document order, deduplicated; single-line plans parse identically to today.
- Delivery state (`tools/delivery/types.ts`) carries the full list (`originIssueNumbers`); existing single-issue state files load without migration.
- `open-pr` for the phase's **final ticket only** appends one `- Closes #<N>` bullet per origin issue to the PR body; earlier tickets' PRs get none (unchanged semantics — issues resolve only when the last stacked PR lands on `closeoutBranch`).
- Near-miss lines (`Origin Issue #76`, `origin issue: 76`, trailing punctuation) are still rejected — the parser stays strict; the preflight format check (`.agents/skills/preflight/SKILL.md`) is updated to validate every `Origin issue` line in the multi-line form and still FAIL on near-misses.
- `docs/template/stubs/product-plan.template.md`, `docs/template/stubs/implementation-plan.template.md`, and `docs/template/delivery/delivery-orchestrator.md` document the multi-line form.

## Red

- Write failing tests in `tools/delivery/test/`:
  - an `## Epic` section with five `Origin issue: #<N>` lines parses to all five numbers in order;
  - a single-line plan parses to a one-element list (back-compat);
  - near-miss formats parse to nothing (strictness preserved);
  - duplicate issue numbers dedupe;
  - final-ticket PR body assembly emits one `Closes` bullet per issue; a non-final ticket emits none.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P21.06): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Extend the parser, state field, and PR-body assembly with the smallest change that passes; keep a deprecated single-value accessor only if call sites make it cheaper than threading the list.

## Refactor

- Collapse any now-duplicated single/multi handling into the list path; no opportunistic cleanup.

## Review Focus

- State back-compat: an in-flight phase recorded with the old single `originIssueNumber` must keep working after upgrade — check `state.json` load paths, not just the parser.
- The final-ticket-only rule survives: grep every consumer of the origin-issue value to confirm none starts emitting `Closes` on intermediate PRs.
- Preflight symmetry: the SKILL.md check and the parser must accept/reject exactly the same forms — a form preflight passes but the parser ignores recreates the silent-skip bug this mechanism just fixed.
- This phase's own final PR (P21.07) is the first consumer — it must close #78, #83, #84, #87, #105.
- Intentionally deferred: comma-separated single-line form (`Origin issue: #78, #83`) — one canonical form, one line per issue.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `adds a Closes line to the final ticket in the phase when originIssueNumbers has one entry` in `tools/delivery/test/pr-metadata.test.ts` failed (no `- Closes #76` in the body), and `planning.test.ts` errored with `SyntaxError: Export named 'parseOriginIssueNumbers' not found` — confirmed via a `git stash` of the four implementation files (planning.ts, state.ts, types.ts, pr-metadata.ts) with the test files kept in place, matching the discipline established earlier in this phase.
Why this path: renamed `parseOriginIssueNumber` to `parseOriginIssueNumbers` outright (returns `number[]`, scoped to the `## Epic` section, `^Origin issue:\s*#(\d+)\s*$` per line, deduplicated) rather than keeping the old name as a wrapper — the only caller was `state.ts`'s `loadPlanContext`, so renaming cost one call-site edit and kept the parser's contract unambiguous. `DeliveryState.originIssueNumber` became `originIssueNumbers?: number[]`; `normalizeDeliveryStateFromPersisted` gained a small legacy-read helper that wraps a persisted single `originIssueNumber` into a one-element array at load time (new field wins when both are present), satisfying "existing single-issue state files load without migration" without a rewrite step. `pr-metadata.ts`'s `buildPullRequestBody` now loops `state.originIssueNumbers ?? []` on the final-ticket branch, emitting one `- Closes #<N>` bullet per issue.
Alternative considered: keeping `originIssueNumber` (singular) as a deprecated accessor computed from `originIssueNumbers[0]`, per the ticket's own "keep a deprecated single-value accessor only if call sites make it cheaper than threading the list." Rejected — there were only two real consumers (`state.ts`, `pr-metadata.ts`), both cheaper to update directly than to add and later remove an accessor.
Deferred: the comma-separated single-line form (`Origin issue: #78, #83`) — explicitly out of scope per the ticket text; one canonical form, one line per issue. Also deferred (found by the adversarial subagent-review pass, not fixed): `syncStateWithPlan`'s `originIssueNumbers ?? existing?.originIssueNumbers` fallback means a re-sync after all `Origin issue:` lines are removed from `## Epic` keeps the previously-recorded issue numbers rather than clearing them, because `loadPlanContext` maps a freshly-parsed empty list to `undefined` before that fallback runs. This is not a P21.06 regression — it is the exact same `??`-fallback-to-existing pattern the pre-P21.06 single-value `originIssueNumber` field already had (removing the one Origin line from a plan never cleared a previously-recorded scalar either). Whether "remove the Origin line(s)" should actively clear a phase's already-tracked issues is a product-semantics question outside this ticket's scope, not a parsing/back-compat bug; left as-is pending explicit product decision. The adversarial review's other actionable finding — the `## Epic` section boundary was not fence-aware, so a `## `-looking line inside a fenced code block prematurely truncated extraction — was a genuine P21.06-introduced gap (the pre-ticket parser never scoped to a section at all) and was fixed via `extractEpicSection`'s fence-tracking line scan, with a regression test.
Contract note: none — `Type: feat`, `Scope: delivery`, `Red: required` all matched the actual change. Mid-ticket, a small unrelated commit (`a5e81438` — `feat(delivery): emit refactor_tdd codogotchi gate before refactor-review prompt`, already on `main`) was cherry-picked into this branch at the operator's explicit request, ahead of continuing P21.06's own implementation; it touches `cli-runner.ts`/`codogotchi-gate.ts`/`p17-03.test.ts` only, no overlap with this ticket's files.
