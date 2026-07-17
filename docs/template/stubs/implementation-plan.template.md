# Phase N — [Phase Title]

> One-sentence description of what this phase delivers and why.

## Epic

[Optional: link to the engineering epic or product doc this phase belongs to.]

[Optional: `Origin issue: #<N>` — if this phase originates from one or more GitHub issues, record each on its own line in this exact format (e.g. five issues → five `Origin issue: #<N>` lines). The orchestrator appends one `- Closes #<N>` bullet per issue to the PR body of this phase's FINAL ticket only (not every ticket's PR) — no issue is actually resolved until that last stacked PR lands on the closeout branch. Near-miss forms (`Origin Issue #76`, `origin issue: 76`, trailing punctuation or prose after the number) are rejected — one issue per line, nothing else on the line.]

## Product contract

[What the user or developer will be able to do when this phase is complete that they cannot do today.]

## Grill-Me decisions locked

[Key decisions resolved during soa-grill-me that are now locked. Format: decision → rationale.]

## Ticket Order

1. `PN.01 [Ticket Title]`
2. `PN.02 [Ticket Title]`
3. `PN.03 [Ticket Title]`

## Ticket Files

- `ticket-01-[slug].md`
- `ticket-02-[slug].md`
- `ticket-03-[slug].md`

## Exit Condition

[Prose describing the shipped state. What is true when this phase is done? What can you demonstrate?]

## CI Baseline

[Run `pnpm run ci:quiet` (or equivalent) on `main` before the first ticket starts and record the result here. This snapshot makes per-ticket CI diffs unambiguous — an agent can tell whether a failure is pre-existing or introduced.]

> Baseline recorded: [date] — [pass / N pre-existing errors: brief summary]

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- [Any additional merge-order or dependency rules.]

## Explicit Deferrals

- [What is intentionally not in scope. Be specific — vague deferrals create scope creep.]

## Stop Conditions

- [When to pause and get developer input rather than continuing.]
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: [Why a retrospective is warranted for this phase.]
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-<N>-<slug>-retrospective.md`
