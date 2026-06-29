---
name: soa-quality-control
description: Guide a post-phase quality-control fix into one verified review-gap ledger record. Use for /soa quality-control phase-NN: <description> and /soa qc phase-NN: <description> after a small fix has exposed learning for future planning or review prompts.
---

# SoA Quality Control

Use this skill for the post-phase quality-control lane after closeout when a
small, verified fix exposes a review gap worth recording.

Triggers:

- `/soa quality-control phase-NN: <description>`
- `/soa qc phase-NN: <description>`

The `phase-NN` argument is required. If it is missing or ambiguous, stop and ask
for the exact phase before inspecting or changing files.

## Scope

This is a guided fix-and-record lane, not a delivery-orchestrator command and
not a replacement for `/soa tao`, standalone PR triage, or new phase planning.

Use it when:

- the phase has already closed out
- the issue is small enough for one bounded fix commit
- a human can verify the fix before capture
- the learning belongs in `docs/product/review-gaps/ledger.jsonl`

Route larger or unclear work toward standalone PR triage or `/soa plan` with a
one-line explanation. Do not hard-gate solely on size when the operator is
already asking for quality-control capture.

## Workflow

1. Parse the required `phase-NN` and the issue description.
2. Inspect the relevant code, docs, tests, prior phase tickets, and review
   artifacts needed to understand the reported gap.
3. Make the smallest prudent fix.
4. Verify with the narrowest meaningful command, then broaden if the touched
   surface warrants it.
5. Ask for or confirm human verification of the fixed behavior before recording
   the review gap. Do not append a ledger row for an unverified fix.
6. Commit the fix. The fix commit is the provenance for the ledger row.
7. Append exactly one JSONL record to `docs/product/review-gaps/ledger.jsonl`
   using the review-gap ledger helper contract from
   `tools/delivery/review-gap-ledger.ts`. Treat this as the `record-review-gap`
   step: one verified fix, one commit, one ledger line. Prefer the optional
   rich-capture fields (`problem`, `solution`, `defectClass`, `testReachability`,
   `recurrence`, `id`) whenever the fix exposes reusable learning — a one-line
   `summary` alone discards the experiential detail that makes the ledger
   valuable for future planning and review prompts.
8. If the learning may deserve future prompt or process changes, add a concise
   candidate to `docs/product/review-gaps/promotion-queue.md`.
9. Run formatting and the relevant verification command after editing the
   ledger or promotion queue.

## Recording Rules

- Record the phase that produced the learning, not the phase that applies the
  fix.
- Use the landed fix commit SHA and subject for `fixCommit`.
- Count how many detection or review rounds were needed before the issue was
  found.
- Bias against `review-reachable`. Use it only when the ticket spec, diff, or
  persisted review artifacts show the reviewer had enough evidence at review
  time to catch the issue and the lesson maps to adversarial-review prompt
  vocabulary.
- Use `spec-gap` when the expected behavior was missing or underspecified in
  the plan, ticket, or acceptance criteria.
- Use `qa-gap` when the issue required experiential, manual, or dogfood
  verification outside the normal code-review surface.
- Use `completeness-gap` when delivered scope was valid but missed adjacent
  work that should be shaped in future planning.
- Do not edit `docs/template/delivery/adversarial-review-template.md` from this
  lane. Capture promotion candidates only, and promote later only after
  recurrence or a clear high-severity single instance.

## Stop Conditions

Stop and ask the operator when:

- the phase argument cannot be resolved to a concrete `phase-NN`
- the fix is not small and bounded
- human verification has not happened and cannot be confirmed
- commit provenance is unavailable
- reachability classification is genuinely ambiguous after reading the evidence
- recording would require changing the ledger schema or overwriting existing
  `docs/product/review-gaps/` content
