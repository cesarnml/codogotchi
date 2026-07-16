# P21.07 Review-gap ledger mining, clause promotion, and phase docs

Size: 2 points
Type: docs
Scope: review
Red: skip

## Outcome

- A new analysis doc `docs/product/review-gap-analysis/codogotchi-ledger-2026-07.md` accounts for **every** review-reachable row in codogotchi's `docs/product/review-gaps/ledger.jsonl` across both schema generations (string `reachability` and `{classification: ...}` object form — 11 rows total at analysis time), with: a table of recurring review-reachable defect classes and verified occurrence counts; a promotion verdict per class against the ≥2–3× bar; and an explicit "not promoting these, and why" list covering spec-gap / completeness-gap / qa-gap / experiential-only / single-occurrence rows.
- Recurrence counts are verified against the current `ledger.jsonl` (including `recurrence` arrays), reconciling `promotion-queue.md`'s claims — where the queue and the ledger disagree, the ledger wins and the discrepancy is named.
- Each promotion-ready class lands as a probeable attack-surface clause in `docs/template/delivery/adversarial-review-template.md` (post-P21.01 tag-form template), phrased in the existing diff-derived classes' style ("For any X, assert Y…"). At minimum, `control-signal-starved-by-change-gated-callback` (3×, at threshold) is promoted unless verification overturns its count — per the phase stop condition, count discrepancies that change promotion decisions go to the developer before the template is edited.
- The promotion-queue caveat is honored in the writeup: classes only review-reachable when both halves ship in one diff are flagged as phase-integration-pass candidates, not silently promoted.
- Phase closeout docs: `README.md` and `docs/template/overview/start-here.md` updated where delivered scope/commands/status changed; the phase retrospective is written to `docs/product/retrospectives/phase-21-subagent-review-contract-and-runner-fidelity-retrospective.md` per the `soa-write-retrospective` skill (retrospective: **required**).
- This ticket's PR is the phase's final PR: its body carries `Closes` bullets for #78, #83, #84, #87, #105 via the P21.06 mechanism.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Human review at the PR is the gate for doc changes.**

## Green

- Read `docs/product/review-gaps/README.md` end to end first (the reachability router is the analysis discipline); be strict about review-reachability — over-crediting bloats the prompt and teaches it nothing.
- Write the analysis, then the template clause(s), then the closeout docs.

## Refactor

- Not applicable (docs-only).

## Review Focus

- Completeness: every review-reachable ledger row is accounted for by id — spot-check the row count against the ledger.
- Count honesty: verify the 3× claim for `control-signal-starved-by-change-gated-callback` directly against ledger rows (`codogotchi-01` round-1, `codogotchi-10`, the phase-19 QC instance) rather than trusting the queue.
- Clause quality: promoted clauses must be probeable invariants a reviewer can act on against a diff, matching the existing seven classes' register — not narrative lessons.
- The "not promoting" section is present and reasoned — it is half the deliverable.
- `Closes` bullets: confirm all five issues appear on this PR's body before requesting final merge approval.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [not applicable — docs-only ticket]
Why this path: [why this analysis/promotion shape was chosen]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
