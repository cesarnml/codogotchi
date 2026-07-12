# P4.02 Docs, guidance, and retrospective

Size: 1 point
Type: docs
Scope: delivery-docs

## Outcome

- `docs/template/delivery/delivery-orchestrator.md` documents which workflow/state-guard errors are contract-bearing and how contributors should treat their machine-readable identity versus human prose
- Contributor-facing docs describe the optional-DI extension rule and the test assertion stance for stable workflow contracts
- Phase 04 retrospective is written at `notes/public/phase-04-orchestrator-contract-stability-retrospective.md`

## Red

Doc-only ticket - no failing test. Instead, assert the docs and retrospective contain the new boundary language before committing:

- Confirm `delivery-orchestrator.md` names the targeted stable workflow/state-guard contract boundary
- Confirm the docs describe the optional-DI rule: optional means the new behavior runs only when the hook is supplied
- Confirm the docs describe the testing stance: stable contract first, prose second

Commit:

```text
docs(P4.02): document workflow contracts and write phase-04 retrospective [P4.02]
```

## Green

**`docs/template/delivery/delivery-orchestrator.md`:**

- Document which delivery-tool workflow/state-guard failures carry stable machine-readable identity
- Document that the human-readable message remains operator guidance and may evolve independently of the stable contract
- Document the optional-DI extension rule for delivery helpers
- Document the test assertion stance for these surfaces

**Additional contributor-facing docs:**

- Update any relevant overview/guidance docs that should reinforce the new contract boundary for future contributors
- Keep the wording narrow to the delivery-tool boundary; do not imply a repo-wide error-framework policy

**Phase 04 retrospective:**

- Read `.agents/skills/write-retrospective/SKILL.md` for section structure and placement conventions
- Write retrospective to `notes/public/phase-04-orchestrator-contract-stability-retrospective.md`
- Evaluate whether the new workflow contract and optional-DI guidance actually reduced false-regression churn during delivery

## Refactor

None - doc-only ticket.

## Review Focus

- Zero `.ts` behavior changes - this is a doc-only ticket
- The docs clearly distinguish stable machine-readable workflow contracts from mutable human-facing prose
- The optional-DI rule is stated plainly enough that a future contributor will not accidentally reintroduce the Phase 03 regression class
- The docs do not overclaim repo-wide error-policy changes beyond the delivery-tool boundary

## Rationale

Why this path: the implementation ticket establishes the boundary in code; this ticket locks that boundary into the repo's contributor guidance and records what was learned from making the contract explicit.

Alternative considered: allowing small cleanup code changes here if documentation surfaced inconsistencies. Rejected because the second ticket is intentionally zero-code so reviewers can validate the contract documentation without hidden behavior drift.

Deferred: any broader cleanup to CLI wording or non-workflow error surfaces discovered while documenting the boundary.

Contract note: this ticket originally omitted `Type:` because the template did not require it when Phase 04 was decomposed. `Scope:` already pointed at docs work, but it is now normalized to `delivery-docs` so the metadata can flow directly into a conventional-commit subject.

Implementation note: the docs deliberately name only the targeted delivery workflow/state guards and the adjacent wrong-worktree guard as contract-bearing. They also make the optional-DI rule explicit as an extension rule for delivery helpers, while avoiding any claim that the repo now has a general error-framework policy.
