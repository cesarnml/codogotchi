# P19.02 Review-gap ledger record helper

Size: 3 points
Type: feat
Scope: quality-control
Red: required

## Outcome

- A repo-local helper can append one review-gap JSONL record to `docs/product/review-gaps/ledger.jsonl`.
- The helper validates required fields, `phase-NN` attribution, date form, commit provenance, positive round count, controlled vocabularies, and append-only output.
- `review-reachable` records require a prompt lesson and concrete review evidence fields; non-review-reachable records do not.
- Tests cover valid append, invalid phase, invalid reachability, invalid round count, and preservation of existing ledger lines.

## Red

- Write failing behavior tests for a new review-gap record helper that appends a valid record to an existing ledger without rewriting prior lines.
- Write failing validation tests for malformed phase, missing commit provenance, invalid reachability, zero or negative rounds, and unsupported kind.
- Write a failing test that `review-reachable` cannot be recorded without the evidence needed to support that claim.
- Run the targeted tests and confirm they fail before implementation.
- Commit with suffix `[red]`: `test(P19.02): cover review-gap ledger records [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Add a focused helper module under `tools/delivery/` for review-gap record validation and JSONL append.
- Use structured validation rather than ad hoc string concatenation.
- Ensure appended records end with one newline and preserve existing ledger bytes before the new line.
- Export only the helper types and functions needed by later QC workflow code.

## Refactor

- Keep review-gap vocabulary centralized in the helper so later tickets do not duplicate the same strings.
- Avoid adding a full CLI command unless P19.03 proves the skill needs one.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Verify commit provenance is captured as a real commit reference and subject, not free-form prose alone.
- Verify append-only behavior cannot reorder or rewrite existing ledger entries.
- Verify validation errors are operator-readable enough for a skill-led workflow.
- Verify this helper does not edit `promotion-queue.md` or the adversarial-review prompt.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: helper tests should fail because no review-gap ledger module exists today.
Why this path: the ledger contract is important enough to test independently of skill prose.
Alternative considered: leave ledger writing entirely to agent instructions; rejected because the phase depends on durable structured records.
Deferred: command invocation and promotion queue guidance belong to later tickets.
Contract note: none.
Implementation note: the helper uses runtime validation with centralized vocabularies, returns the normalized record for callers, and appends bytes only. If an existing ledger is non-empty but lacks a trailing newline, the helper appends a newline boundary before the new JSON line without rewriting prior bytes.
Subagent finding: the first pass allowed `kind` and `reachability.classification` to diverge, which could claim `review-reachable` while bypassing evidence and prompt-lesson validation. The helper now requires those fields to match.
