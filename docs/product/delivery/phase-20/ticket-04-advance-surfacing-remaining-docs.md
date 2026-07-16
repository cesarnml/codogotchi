# P20.04 Advance-time surfacing & remaining docs

Size: 2 points
Type: feat
Scope: delivery
Red: required

## Outcome

- `advance` reads the just-completed ticket's `reviews/<ticket>-refactor-review.ledger.json` (when present) and prints any `deferred` rows (summary + reason) to console/handoff output as part of its existing per-ticket-boundary output, so a human sees them at the next natural stopping point rather than only in a post-phase sweep.
- When no refactor-review ledger exists for the ticket (e.g. `refactorReview: "disabled"`, `Red: skip`, doc-only), `advance` prints nothing extra — no error, no empty-section noise.
- `.agents/skills/son-of-anton-ethos/SKILL.md` updated so its execution-mechanics and stop-condition sequencing account for the new gate the same way it already accounts for the adversarial gate.
- `notes/public/refactor-advisory-subagent-design.md` header updated from `Status: PROPOSED` to `Status: IMPLEMENTED`, with a pointer to `docs/product/plans/phase-20-subagent-refactor-review.md` and `docs/product/delivery/phase-20/implementation-plan.md`.
- `docs/template/overview/start-here.md` / `README.md` touched only if their exact command-sequence listings need the new steps inserted for accuracy (confirm during implementation; do not add speculative mentions if the existing text doesn't enumerate the adversarial gate's steps at that level of detail either).

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.** This ticket does not qualify — the `advance` surfacing logic is testable code, even though most of the diff is documentation.
- Write a failing test that `advance` prints deferred refactor-review rows (summary + reason) for the ticket it just completed.
- Write a failing test that `advance` prints nothing extra when no refactor-review ledger exists for the completed ticket.
- Write a failing test that `advance` prints nothing extra when the refactor-review ledger exists but has zero `deferred` rows (all accepted/rejected).
- Run the targeted tests and confirm they fail before implementation.
- Commit with suffix `[red]`: `test(P20.04): cover advance-time deferred refactor-suggestion surfacing [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Add the ledger-read-and-print step to `advance`'s existing output path in `cli-runner.ts` (or `format.ts`, wherever `advance`'s console output is assembled).
- Implement the smallest logic that makes the new tests pass.
- Update `.agents/skills/son-of-anton-ethos/SKILL.md` and flip the design note's status header.

## Refactor

- Keep the print format simple and consistent with how `advance` already surfaces other per-ticket information — no new formatting subsystem for one field.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Confirm the "nothing extra when no ledger / no deferred rows" cases are actually silent — a chatty `advance` on every ticket regardless of policy would be worse than the phase-end-only status quo this is meant to improve on.
- Confirm the design note's `Status: IMPLEMENTED` update accurately reflects what shipped (two-state policy, no strict mode, no auto-enable) rather than restating the original proposal's full three-state ambition.
- Confirm `son-of-anton-ethos/SKILL.md`'s changes don't alter its behavior for repos running with `refactorReview: "disabled"` (the default) — the ethos skill must not assume the gate is on.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `formatDeferredRefactorSuggestions` not exported from `tools/delivery/refactor-review.ts`.
Why this path: split the surfacing logic into two pure functions (`extractDeferredRefactorReviewRows`, `formatDeferredRefactorSuggestions`) plus a thin CLI-side I/O wrapper (`printDeferredRefactorSuggestionsForAdvance`), matching the repo's convention of unit-testing the pure logic directly rather than the CLI dispatch switch. `formatDeferredRefactorSuggestions` returns `undefined` (not `''`) for zero rows specifically so the caller's `if (message)` check suppresses output correctly.
Alternative considered: making `advance` always print a "Refactor review: N deferred suggestions" line even when N=0, for consistency with other always-present status fields. Rejected per the ticket's own Review Focus — a chatty `advance` regardless of policy is explicitly the failure mode this ticket exists to avoid, not just for the zero-deferred case but for tickets where the gate never ran at all.
Deferred: nothing beyond what tickets 20.01–20.03 already deferred (`runner_on_red_strict`, automated follow-up ticket creation, pilot-metrics tooling).
Contract note: none — `Type:` and `Scope:` match the implementation plan.
