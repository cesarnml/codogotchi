# Phase 01 — CLI Bug Fixes

> Fix two delivery CLI bugs that have caused real failures across coding-stats phases 03 and 04.

## Epic

[docs/product/plans/phase-01.md](../../01-product/phase-01.md)

## Product contract

After this phase ships:

- `closeout-stack` runs cleanly after a multi-worktree gated delivery without manual `state.json` edits
- Every PR opened by the orchestrator has a title in the form `type(scope): subject [PXX.XX]` derived from the ticket, never from the red test commit

## Grill-Me decisions locked

- **`codex-preflight` guard fix deferred** → command is disabled in current config and killed in Phase 02; fixing it is waste
- **Ticket type source → filename convention** (`ticket-NN-<type>-<slug>.md`) → AI writes all tickets; filename and content are consistent, no drift risk
- **Ticket scope source → `Scope:` metadata line in ticket doc** → parsed at plan-load time into `TicketDefinition`; scope describes the area of codebase touched; omitted if absent
- **`buildPullRequestTitle` removes `commitSubject` param entirely** → title derives from ticket fields only; commit order becomes irrelevant

## Ticket Order

1. `P1.01 Fix state.json sync in advance`
2. `P1.02 PR title derived from ticket content`

## Ticket Files

- `ticket-01-fix-state-sync.md`
- `ticket-02-feat-pr-title.md`

## Exit Condition

Both tickets merged to main with passing CI. `closeout-stack` runs end-to-end on a multi-worktree delivery without intervention. PRs opened by the orchestrator show `fix(cli): ...` and `feat(pr-metadata): ...` style titles.

## CI Baseline

> Baseline recorded: historical placeholder — this repo uses Bun, not pnpm. For new baselines, run `bun test` or the repo's current verification gate instead of `pnpm test`.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** do not block a ticket; newly introduced failures do.

## Explicit Deferrals

- `codex-preflight patched <sha>` guard inversion (Phase 02 kills the command)
- `post-verify-self-audit` → `post-verify` rename (Phase 02)
- `selfAudit` removal from config schema (Phase 02)
- `RESUME COMMAND` guard in generated handoff (Phase 02)
- Orchestrator ergonomics: worktree guard, `status` next-command, doc-only early failure (Phase 03)

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- `findPrimaryWorktreePath` returns unexpected results in the advance test environment — pause and investigate before writing the sync logic.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: skip
Why: Targeted bug fixes with no workflow or operator behavior changes.
