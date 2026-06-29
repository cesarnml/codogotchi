# Review Gaps

This directory stores post-phase quality-control learning artifacts.

Use this scaffold after a phase is closed out and a small verified fix exposes
a review gap that should inform future planning or review prompts.

## Files

- `ledger.jsonl` is append-only. Each landed fix gets one JSON object line.
- `promotion-queue.md` collects candidates for later prompt or process
  promotion. Capture here does not edit the adversarial-review prompt directly.

## Record fields

Write ledger rows through the `appendReviewGapRecord` helper in
`tools/delivery/review-gap-ledger.ts`, which validates the schema.

Required on every row:

- `phase` (`phase-NN`), `date` (`YYYY-MM-DD`), `kind` (a classification below),
  `summary` (one-line headline), `fixCommit` (`{ sha, subject }`),
  `detectionRounds` (how many detection/review rounds before it was found),
  `reachability` (`{ classification, evidence?, promptLesson? }`).

Optional rich-capture fields — ported from the pioneering codogotchi ad-hoc
quality-control ledger — carry the experiential detail a one-line `summary`
cannot. Prefer them whenever a fix exposes reusable learning:

- `id` — a repo-scoped ledger identifier (e.g. `codogotchi-16`).
- `problem` — the precise failure, in enough detail to reconstruct it.
- `solution` — what the landed fix actually changed.
- `defectClass` — a short reusable label for the defect family.
- `testReachability` — whether/how the gap was reachable by automated tests.
- `recurrence` — array of prior ledger `id`s this finding recurs from.

Slim rows (no rich fields) stay valid; the rich fields are additive.

## Classification

Record the narrowest honest gap class:

- `review-reachable` when a per-ticket reviewer could have caught the issue
  from the ticket spec, diff, and review artifacts available at review time.
- `spec-gap` when the expected behavior was not specified clearly enough.
- `qa-gap` when the issue required experiential or manual verification outside
  the normal code-review surface.
- `completeness-gap` when delivered scope was valid but missed adjacent work.

When uncertain, avoid overstating review reachability. Record the ambiguity in
the ledger entry and route the learning conservatively.

## Evidence

`review-reachable` is a conservative classification. A ledger entry should name
the specific ticket spec, diff surface, review artifact, or prompt clause that
made the issue visible to a normal per-ticket reviewer. If the evidence depends
on hindsight, cross-phase context, local dogfooding, or unstated product intent,
choose another class.

Use the same defect vocabulary as the adversarial-review template when it
actually fits the evidence. Do not invent a prompt lesson just to make a fix
look review-reachable.

## Routing

- Route `review-reachable` findings to the promotion queue when the lesson could
  improve future adversarial review.
- Route `spec-gap` findings toward future planning, ticket acceptance criteria,
  or `/soa plan` when the missing behavior is larger than one bounded fix.
- Route `qa-gap` findings toward manual QA, dogfood notes, or operator
  verification checklists.
- Route `completeness-gap` findings toward future phase shaping or a standalone
  PR when the adjacent work is small and independently reviewable.

Routing is advisory. Quality control can still capture a small verified fix
without forcing the operator into a larger workflow.

## Promotion

Quality control captures learning; it does not directly edit
`docs/template/delivery/adversarial-review-template.md`.

Add a promotion candidate only when the lesson is reusable beyond the immediate
fix. Prefer recurring findings before changing global prompt guidance. A single
high-severity finding may justify promotion, but the queue entry should explain
why the one case is enough.

Promotion candidates should be concrete clauses or checks, not broad reminders.
The later promotion edit should decide whether the candidate belongs in planning
guidance, ticket templates, process docs, or the adversarial-review prompt.
