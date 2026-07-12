# P19.05 Operator docs and retrospective

Size: 2 points
Type: docs
Scope: quality-control
Red: skip

## Outcome

- `README.md`, `AGENTS.md`, `AGENTS.soa.md`, and `docs/template/overview/start-here.md` document `/soa quality-control` and `/soa qc` beside the post-phase `/soa tao` lane.
- Delivery docs explain how QC relates to closeout, standalone PR triage, planning, and future adversarial-review prompt improvement.
- The required Phase 19 retrospective is written at `docs/product/retrospectives/phase-19-quality-control-review-gaps-retrospective.md`.
- The phase docs accurately describe final delivered behavior and deferrals.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**
- No red test is required unless implementation introduces non-doc behavior.

## Green

- Add QC discoverability to root and template operator docs.
- Document the expected sequence: closeout, optional `/soa tao`, post-phase `/soa quality-control` for verified fixes, then future planning or prompt promotion when warranted.
- Use `soa-write-retrospective` for retrospective structure and placement.
- Update the implementation plan or ticket rationales if final behavior differs from the planned contract.

## Refactor

- Remove stale or duplicate QC wording from earlier tickets if documentation drift appears.
- Keep command lists consistent across README, AGENTS files, template overview, and SoA entrypoint.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Verify operators can discover QC without knowing the originating GitHub issue.
- Verify docs do not imply QC replaces `/soa tao`, ticket review, or closeout.
- Verify the retrospective names any process confusion, prompt-bloat risk, or schema friction found during delivery.
- Verify final deferrals remain explicit.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: skip because this is documentation and retrospective work.
Why this path: final docs should be written after behavior and skill wording are stable.
Alternative considered: spread docs updates across every ticket; rejected because final cross-doc consistency is easier to review once the lane exists.
Deferred: cross-repo analytics docs and prompt-promotion automation docs remain out of scope.
Contract note: none.
