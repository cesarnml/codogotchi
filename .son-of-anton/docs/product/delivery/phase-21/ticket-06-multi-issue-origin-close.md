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

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
