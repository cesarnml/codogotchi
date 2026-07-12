# Phase 19: Quality-Control Review Gaps

**Delivery status:** Product plan approved; ticket decomposition written for preflight.

## TL;DR

**Goal:** Add a first-class post-phase quality-control lane that captures verified fixes as review-gap learning instead of letting the lessons disappear into ordinary commits.

**Ships:**

- `/soa quality-control phase-NN: <description>` and `/soa qc phase-NN: <description>` as discoverable post-closeout commands
- A synced `docs/product/review-gaps/` scaffold for consumer repos, including schema docs, append-only JSONL ledger, and promotion queue
- A verified-fix recording discipline: one human-verified fix, one commit, one ledger line with commit provenance and round count
- Product guidance that routes each review gap toward review prompt improvement, future planning, QA, or completeness work without turning those suggestions into hard gates
- Documentation that positions quality control as a sibling to post-phase advisory-observation triage

**Defers:**

- Automatic promotion of review-gap lessons into the upstream adversarial-review prompt
- Replacing `/soa tao` or changing ticket-by-ticket review gates
- A full database, dashboard, or analytics product for cross-repo review-gap aggregation
- Enforcing implementation routes for fixes that are larger than the quality-control lane

---

Son of Anton already treats phase delivery as a controlled workflow, but real defects and polish gaps still surface after closeout through dogfooding and QA. Today those fixes can land as ordinary commits without preserving the more valuable question: why did the existing planning, spec, test, or review loop miss this?

This phase makes that post-phase learning loop explicit. A quality-control command should help operators fix small post-phase issues, record the verified fix only after it lands, classify whether the gap was review-reachable, and stage recurring review lessons for possible future prompt promotion. The workflow exists as prior art in the `codogotchi` consumer repo; Phase 19 promotes the pattern into Son of Anton so every synced consumer can use it without copy-paste.

## Phase Goal

This phase should leave the product in a state where:

- An operator can invoke `/soa quality-control phase-NN: <description>` or `/soa qc phase-NN: <description>` after phase closeout and get guided through a post-phase fix capture flow
- A fresh consumer repo that runs `soa-sync.sh` has a `docs/product/review-gaps/` home with a documented schema, empty append-only ledger, and promotion queue stub
- Each recorded item represents exactly one verified fix commit, captures the real commit provenance, and includes the number of propose-verify rounds before landing
- Review-gap classification is conservative: `review-reachable` must be earned by citing what a per-ticket reviewer could actually see, while spec, qa, and completeness gaps route elsewhere
- Operators can see which fixes might eventually inform the adversarial-review prompt without the quality-control command editing that prompt directly

## Committed Scope

### Quality-Control Command

- Add `/soa quality-control` with `/soa qc` as an alias in the SoA entrypoint.
- Require an explicit `phase-NN` argument so concurrent hardening work remains attributable to the phase that produced the gap.
- Treat quality control as a post-closeout lane for small verified fixes and review-gap capture, adjacent to `/soa tao`.
- Suggest, but do not enforce, another path when the reported item is ticket-sized, phase-sized, or architectural.
- Keep existing repo pre-commit expectations in force for any fix that lands through this lane.

### Verified Fix Recording Discipline

- The command guides the operator through the sequence: implement, human verifies, repeat if needed, commit, record.
- A ledger line is written only after the fix commit exists and the human has verified the behavior.
- The record captures one verified fix per line, including date, phase, commit, kind, round count, problem, solution, defect class, reachability, test reachability, recurrence, and prompt lesson when applicable.
- When a proposed fix misses, the workflow should bias toward instrumentation and observation before the next attempt, then strip temporary diagnostics before the final verified commit.

### Review-Gap Artifacts

- Ship a consumer-facing `docs/product/review-gaps/` scaffold through the sync/template path.
- Include `README.md` for schema and controlled vocabulary, empty `ledger.jsonl` as the canonical append-only store, and `promotion-queue.md` for candidate review clauses.
- Preserve JSONL as the ledger format so multiple consumer repos can be concatenated for later cross-repo analysis.
- Port the proven shape from the `codogotchi` prior art rather than designing a new taxonomy from scratch.

### Conservative Reachability Routing

- Make `review-reachable` the hardest classification to claim: it requires a concrete diff hunk and ticket clause that a per-ticket reviewer had in front of them.
- Default uncertain cases away from review blame and toward `spec-gap`, `qa-gap`, or `completeness-gap`.
- Use routing as guidance: review-reachable items can feed the promotion queue, spec gaps can feed planning, qa-gap items belong in QA/dogfood learning, and completeness gaps can feed ideation.
- Keep capture separate from promotion. The command may append ledger rows and queue candidates, but it must not edit the upstream adversarial-review prompt.

### Discoverability And Documentation

- Document the quality-control lane beside `/soa tao` in operator-facing docs.
- Explain the review-gap artifacts and command in README and agent guidance so the workflow survives sync into consumer repos.
- Link defect-class vocabulary back to the adversarial-review template so operators classify gaps consistently.
- Make clear that larger work should be suggested toward standalone PR triage or `/soa plan`, not blocked inside the quality-control command.

## Explicit Deferrals

- **Prompt promotion automation:** Phase 19 does not edit `docs/template/delivery/adversarial-review-template.md` from quality-control records. Promotion remains deliberate future work after recurrence is visible.
- **Hard routing gates:** Quality control suggests standalone PR or planning paths for larger work, but it does not refuse to proceed based on size classification alone.
- **Cross-repo analytics tooling:** No dashboard, merge job, or reporting command is required beyond the JSONL format that allows later aggregation.
- **Changing ticket review mechanics:** The pre-PR subagent review, external PR review, and closeout gates are consumers of future lessons, not surfaces this phase redesigns.
- **Backfilling historical ledgers:** The `codogotchi` prior art informs the scaffold, but Phase 19 does not require importing every historical consumer repo entry into this source repo.
- **Schema migration framework:** The first shipped scaffold can define the contract; automated migrations for future ledger schema changes are deferred until there is real schema churn.

## Exit Condition

Phase 19 is done when a consumer repo synced from Son of Anton can discover and invoke `/soa quality-control phase-NN: <description>` or `/soa qc phase-NN: <description>`, receive guidance that preserves the verified-fix-before-recording discipline, and record a post-phase fix into `docs/product/review-gaps/ledger.jsonl` with phase attribution, commit provenance, round count, reachability routing, and promotion separation.

The phase is also done when a fresh consumer sync includes the review-gap scaffold and the primary operator docs explain where quality control fits relative to closeout, `/soa tao`, standalone PR triage, planning, and adversarial-review prompt improvement.

## Retrospective

`required` - This phase introduces a durable post-phase operator workflow and a learning artifact that can influence future review policy, so closeout should capture whether the lane improved review-gap honesty without creating prompt bloat or process confusion.
