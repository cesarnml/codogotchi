# P20.03 Gate placement, guards & core docs

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- For a `Red: required` ticket under `refactorReview: "runner_on_red"`, the orchestrator's step sequence places the refactor gate (`write-subagent-refactor-review` → `subagent-refactor-review` → `reconcile-subagent-refactor-review`) after `post-verify` and before `write-subagent-adversarial-review`.
- `Red: skip` tickets, doc-only tickets, and `refactorReview: "disabled"` all bypass the refactor gate structurally — no prompt/runner/reconcile steps required or attempted.
- Enforcement is soft per the approved product plan: if the refactor-review artifact is somehow missing, `open-pr` does not hard-block (unlike the adversarial gate's `required` policy). This matches `runner_on_red`'s documented meaning — the happy-path sequence always runs it, but there is no fail-closed guard yet (that's `runner_on_red_strict`, explicitly out of scope).
- `docs/template/delivery/delivery-orchestrator.md`: `Critical Step Order` list updated to include the three new steps in position; new section mirroring "Subagent adversarial review (ticket stacks)" added immediately before that section; `Commands` reference table updated with the four new commands from ticket 20.02.
- `docs/template/delivery/tdd-workflow.md`: Refactor leg description updated from agent discretion to describing the gate.

## Red

- Write a failing test that a `Red: required` ticket under `runner_on_red` cannot transition directly from `post-verify` to `write-subagent-adversarial-review` — the orchestrator must see the refactor gate's steps complete first.
- Write a failing test that a `Red: skip` ticket bypasses the refactor gate with no error.
- Write a failing test that a doc-only ticket bypasses the refactor gate with no error, regardless of `refactorReview` value.
- Write a failing test that `refactorReview: "disabled"` allows the existing `post-verify` → `write-subagent-adversarial-review` sequence unchanged (no new required step).
- Write a failing test that a missing refactor-review artifact does **not** block `open-pr` under `runner_on_red` (soft enforcement) — assert this explicitly so a future `runner_on_red_strict` ticket has a clear test to invert.
- Run the targeted tests and confirm they fail before implementation.
- Commit with suffix `[red]`: `test(P20.03): cover refactor gate placement and bypass rules [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Wire the sequencing guard into the existing workflow-state machine (wherever `write-subagent-adversarial-review`'s current precondition check on ticket status lives) so it requires the refactor gate's completion first when applicable.
- Implement the smallest logic that makes the new tests pass — reuse the existing bypass conditions (`Red: skip`, doc-only detection) already used by the adversarial gate rather than reimplementing that detection.
- Update `delivery-orchestrator.md` and `tdd-workflow.md`.

## Refactor

- Keep the new doc section's structure parallel to "Subagent adversarial review (ticket stacks)" so a reader can visually diff the two and see exactly what differs (brief, tag name, command names, soft vs. required enforcement).
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Confirm `refactorReview: "disabled"` truly leaves today's adversarial-only flow byte-for-byte unchanged in behavior — this is the highest-risk regression surface in the whole phase, since every existing ticket in every consumer repo runs through this code path today.
- Confirm the soft-enforcement behavior (no `open-pr` hard block on missing artifact) is deliberate and tested, not an oversight — a reviewer unfamiliar with the `runner_on_red` vs `runner_on_red_strict` distinction could easily read this as a bug.
- Confirm doc-only and `Red: skip` bypass logic is reused, not reimplemented, from the adversarial gate's existing detection.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `write-subagent-adversarial-review` did not exist as a testable gate against `requiresRefactorReviewBeforeAdversarial` — the module export didn't exist yet, so the new test file's import threw at load time.
Why this path: extracted the guard condition into a pure, standalone predicate (`requiresRefactorReviewBeforeAdversarial`) rather than inlining the four-condition check directly in the CLI case block, so the sequencing rule is independently unit-testable without needing a full CLI-dispatch harness — consistent with how this repo tests other orchestrator guards (`decideSubagentReviewMode`, `reconcileReview`) as pure functions.
Alternative considered: adding a new `TicketStatus` enum value (e.g. `refactor_review_complete`) to represent gate completion in the main status machine. Rejected because ticket 20.02 deliberately kept `recordRefactorReviewOutcome` non-status-mutating to avoid colliding with the adversarial gate's `verified -> subagent_review_complete` transition; introducing a status value here would have required touching that transition logic too, which is out of this ticket's stated scope (guards + docs, not a status-machine redesign).
Deferred: `runner_on_red_strict` fail-closed enforcement on `open-pr` — explicitly out of phase scope per the implementation plan.
Contract note: none — `Type:` and `Scope:` match the implementation plan.

Also fixed in the P20.02 branch during this ticket's start: a literal NUL byte had been committed in `readWorktreeFingerprint`'s `.join(' ')` call (see ticket 20.02's implementation), making `tools/delivery/cli-runner.ts` a binary file from git's perspective. Found via `file` reporting "data" instead of "text" when grep/read tools silently returned no matches on that file. Fixed with a follow-up commit on the P20.02 branch (pushed, updating PR #107), then this ticket's branch was rebased onto the corrected commit before any P20.03 work began.
