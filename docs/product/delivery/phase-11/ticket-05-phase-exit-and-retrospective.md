# P11.05 Phase exit and retrospective

Size: 1 points
Type: chore
Scope: delivery

## Outcome

- Every bullet in the product plan's "Exit Condition" section is demonstrably true on the merged stack.
- `README.md` and `docs/template/overview/start-here.md` are checked for user-visible behavior, command, or status drift introduced by P11.01–P11.04; any drift is fixed.
- `docs/product/retrospectives/phase-11-subagent-review-class-absorption-and-artifact-honesty-retrospective.md` is written using the `soa-write-retrospective` skill at `.agents/skills/write-retrospective/SKILL.md`.
- The delivery-status line at the top of `docs/product/plans/phase-11-subagent-review-class-absorption-and-artifact-honesty.md` reflects "Shipped" (or the canonical post-phase status string used by recent phases — verify against phase-10's post-merge state).
- `bun run ci` is green on the closeout branch.

## Red

- **Doc-only ticket — skip Red.** No automated test required.

## Green

- Walk the product plan's Exit Condition section bullet-by-bullet against the merged stack. Fix any gap inline or open a follow-up ticket (do not silently pass).
- Run README and start-here drift check; update if needed.
- Invoke the `soa-write-retrospective` skill to draft the retrospective. Place it at the path named above.
- Update the product plan's delivery-status line.

## Refactor

- None expected. If the exit-condition walk surfaces small inline cleanups, do them — but anything beyond a few lines should open a follow-up, not bloat this ticket.

## Review Focus

- Retrospective coverage of the four durable boundaries named in the product plan's Retrospective section (runner-invocation contract, structured persistence schema, ethos contract change, phase-12/13 underwriting).
- Whether the absorption-claim validation prediction is recorded — phase-11 cannot validate it; downstream consumer phases will.
- README / start-here drift — easy to miss when the deliverables are tooling-internal.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
