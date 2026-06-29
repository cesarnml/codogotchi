# P19.04 Routing, reachability, and promotion discipline

Size: 2 points
Type: docs
Scope: quality-control
Red: skip

## Outcome

- The quality-control skill and review-gap scaffold docs make `review-reachable` a conservative classification.
- `spec-gap`, `experiential-only`, and `completeness-gap` route to planning, QA/dogfood learning, and ideation respectively.
- Larger items are suggested toward standalone PR triage or `/soa plan` with one-line justification, not hard-gated.
- Capture and promotion stay separate: QC may append ledger rows and queue candidates, but it does not edit the adversarial-review prompt.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**
- No red test is required unless implementation introduces non-doc behavior.

## Green

- Update `.agents/skills/quality-control/SKILL.md` with the bias-against-review-reachable rule.
- Update `docs/template/review-gaps/README.md` with reachability vocabulary, evidence requirements, routing suggestions, recurrence, and promotion queue guidance.
- Ensure `promotion-queue.md` explains candidate clauses and the recurrence bar without implying automatic promotion.

## Refactor

- Keep authoritative vocabulary in the scaffold README and point the skill to it where possible.
- Remove duplicate or conflicting definitions if P19.03 introduced temporary wording.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Verify the wording does not over-credit per-ticket review for gaps reviewers could not see.
- Verify routing remains advisory and does not block operators from fixing small issues.
- Verify prompt promotion is described as a later deliberate action after recurrence.
- Verify defect-class guidance links back to the adversarial-review template vocabulary.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: skip because this ticket should be documentation and skill-instruction refinement only.
Why this path: the main risk is operator misclassification, which belongs in the skill and scaffold contract.
Alternative considered: enforce reachability classification entirely in code; rejected because the hard part is evidence judgment, not enum parsing.
Deferred: automatic promotion and cross-repo analysis remain out of scope.
Contract note: none.
