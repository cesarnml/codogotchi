# Phase 19 Retrospective — Quality-Control Review Gaps

## Scope delivered

Five-ticket stack delivering the post-phase quality-control lane:

- **P19.01** — `docs/product/review-gaps/` scaffold sync: idempotent directory, `ledger.jsonl`, and `promotion-queue.md` created by `soa-sync.sh` in consumer repos. PR [#97](https://github.com/cesarnml/son-of-anton/pull/97).
- **P19.02** — `record-review-gap` helper in `tools/delivery/review-gap-ledger.ts`: validates schema, appends one JSONL row per verified fix. PR [#98](https://github.com/cesarnml/son-of-anton/pull/98).
- **P19.03** — `soa-quality-control` skill and `/soa quality-control` / `/soa qc` dispatcher in the `/soa` entrypoint. PR [#99](https://github.com/cesarnml/son-of-anton/pull/99).
- **P19.04** — Classification discipline docs: `review-reachable` / `spec-gap` / `qa-gap` / `completeness-gap` vocabulary, routing guidance, and promotion separation. PR [#100](https://github.com/cesarnml/son-of-anton/pull/100).
- **P19.05** — Operator discoverability docs and this retrospective. PR #101.

## What went well

**Scaffold-first sequencing held.** Making `docs/product/review-gaps/` exist before the ledger helper, skill, or docs referenced it meant each ticket had a stable artifact home to verify against. No ticket had to defensively handle "directory may not exist."

**One-record-per-verified-fix discipline was easy to enforce via the helper.** Concentrating the schema, validation, and append logic in `review-gap-ledger.ts` kept later tickets from duplicating or drifting that contract. The skill just calls the helper; it does not re-implement append logic in prose.

**Capture-is-not-promotion boundary was clear once stated.** The rule that QC may not edit `adversarial-review-template.md` gave every ticket a clean constraint to test against. Promotion candidates land in `promotion-queue.md` and stay there until a recurrence or high-severity signal justifies a separate edit.

**Classification vocabulary reduced ambiguity at the decision point.** The four categories (`review-reachable`, `spec-gap`, `qa-gap`, `completeness-gap`) with a bias toward the non-`review-reachable` options gave operators a place to land without over-claiming that every fix reflects a reviewer's blind spot.

## Pain points

**`review-reachable` naming is fragile.** The category is the one that feeds back into adversarial-review prompt design, so getting it right matters. But "reachable" is a reasoning claim about what a reviewer _could_ have seen, not what they _did_ see. This is inherently hard to assess at QC time and is expected cost for the approach — any classification system that distinguishes prompt-improvable gaps from other gaps requires this judgment call.

**Skill routing prose required careful hedging.** The skill should not hard-gate on size (a small edge-case fix is QC-appropriate even if a reviewer feels uncertain), but it also should not silently absorb ticket-scale work. Getting that balance to read naturally required several passes.

**Operator sequence is not enforced.** The expected post-phase order (closeout → `/soa tao` → `/soa qc`) is documented but not machine-enforced. An operator could run QC before TAO or before closeout. This was an explicit deferral but will remain a latent gap if adoption grows.

## Surprises

**The scaffold sync needed idempotency for the _entire_ subtree, not just the directory.** Initial design assumed an empty `review-gaps/` directory would always exist after sync. But consumers who ran an earlier sync without Phase 19 had no `review-gaps/` at all, while consumers who had already created their own `ledger.jsonl` content needed the sync to leave it alone. Both cases were handled by the idempotency contract in `soa-sync.sh`, but the dual case (directory exists, file does not) needed an explicit test path.

**The `/soa` dispatcher needed a dedicated `quality-control` command block, not a redirect.** Early design considered routing `/soa qc` to the skill via a one-liner redirect in the dispatcher. But the skill description and argument format (`phase-NN: <description>`) differ enough from other commands that callers need the full description to know what they are triggering. A dedicated command block was the right call.

**TAO and QC are parallel lanes, not sequential gates.** Initial framing implied QC always follows TAO. After delivery, the cleaner model is: they are independent post-phase lanes that both feed the same learning corpus. Operators with no advisory observations can run QC without TAO, and vice versa. The "expected sequence" in docs now reflects this.

## What we'd do differently

**Write the classification vocabulary before the skill, not alongside it.** P19.04 defined `review-reachable` and its siblings, but P19.03 had already used the terminology in the skill. The result was that skill wording and classification docs were written in two tickets without a shared canonical source, requiring consistency passes across both. A better decomposition would have locked the vocabulary in a single doc early and had the skill import those definitions explicitly.

**Make the ledger row schema machine-checkable from the start.** `review-gap-ledger.ts` validates the schema on append, but there is no standing check that reads `ledger.jsonl` and validates existing rows during CI. A future `bun run verify` extension could add a fast JSONL schema check so ledger drift is caught at commit time rather than at QC invocation.

## Net assessment

Phase 19 delivered the stated goals: a fresh consumer sync creates `docs/product/review-gaps/`, `/soa quality-control` and `/soa qc` are discoverable through the SoA entrypoint, and the QC lane can guide a verified post-phase fix into one append-only JSONL ledger record with phase attribution, commit provenance, round count, conservative reachability routing, and promotion separation. Operator docs explain how QC relates to closeout, `/soa tao`, standalone PR triage, and future planning. All explicit deferrals remain explicit and unchanged.

## Follow-up

- Add a fast JSONL schema validation step to `bun run verify` so ledger drift is caught at commit time. Candidate for a standalone PR or early Phase 20 task.
- Track recurrence of `review-reachable` entries in `promotion-queue.md`. If the same surface appears twice before the next full phase, that is the trigger to edit `adversarial-review-template.md`.
- Consider enforcing the post-phase sequence (closeout → TAO → QC) with a lightweight prerequisite check in the QC skill if adoption reveals confusion about when to invoke it.

---

_Created: 2026-06-28. PRs [#97](https://github.com/cesarnml/son-of-anton/pull/97), [#98](https://github.com/cesarnml/son-of-anton/pull/98), [#99](https://github.com/cesarnml/son-of-anton/pull/99), [#100](https://github.com/cesarnml/son-of-anton/pull/100), #101._
