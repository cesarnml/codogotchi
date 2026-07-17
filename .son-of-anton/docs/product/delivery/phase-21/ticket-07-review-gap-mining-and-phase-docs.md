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

Red first: not applicable — docs-only ticket, `Red: skip` per metadata.
Why this path: read codogotchi's `docs/product/review-gaps/ledger.jsonl` (55 rows, found at `/Users/cesar/code/codogotchi`, not in this repo) and its `promotion-queue.md` directly rather than trusting the queue's stated verdicts, per the ticket's explicit "Count honesty" review focus. Machine-counted every row's `reachability`/`reachability.classification` (script, not by-eye) to get an authoritative 11 `review-reachable` rows out of 55. Promoted two classes into `adversarial-review-template.md` as clauses 8 and 9, phrased abstractly (no codogotchi-specific naming) matching the register of the existing seven classes, per explicit operator correction mid-ticket — the ledger provenance and evidence live in the analysis doc, not in the prompt clause itself.
Alternative considered: promoting every class the codogotchi promotion-queue.md marked "AT THRESHOLD" (three candidates were so marked). Rejected for two of the three: `side-effect-call-dropped-or-mis-targeted-in-refactor` and `new-enum-case-skips-existing-transition-matrix` both mix `review-reachable` occurrences with `qa-gap`/legacy-classified occurrences in their recurrence count, and the promotion queue's own writeup for both explicitly says the class needs to be split (a review-prompt clause for one manifestation, a phase-integration/dogfood checklist for another) before a single clause can honestly represent it — promoting either as a single clause now would misrepresent what a diff-only reviewer could actually catch. Only `control-signal-starved-by-change-gated-callback` had a clean same-diff review-reachable core across its confirmed occurrences.
Deferred: designing the phase-closeout/integration-checklist mechanism for the two flagged phase-integration-pass candidates (`compound-widget-cohesion-under-transform`, the mixed refactor-drops-behavior family) — out of scope per the ticket text ("flagged... not silently promoted", no instruction to design the checklist itself). Also deferred: relabeling the 3 legacy-schema ledger rows (`test-isolation-gap` ×1, `adversarial-review-gap` ×2) under the current four-value classification enum — a judgment call outside this ticket's scope.
Contract note: none — `Type: docs`, `Scope: review`, `Red: skip` all matched the actual change (docs-only branch, no code touched).
