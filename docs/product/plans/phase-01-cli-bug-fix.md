# Phase 01: CLI Bug Fixes

**Delivery status:** Decomposed and delivered — `docs/product/delivery/phase-01/` exists and the phase tickets have already shipped.

## TL;DR

**Goal:** Fix three known bugs in the current delivery CLI that have caused real failures across multiple phases.

**Ships:**

- `closeout-stack` runs after multi-worktree delivery without manual `state.json` edits
- PR title format is `type(scope): <ticket-derived subject> [PXX.XX]` — never the red test commit subject

**Defers:** `codex-preflight` guard fix (command is disabled in current config and killed in Phase 02 — not worth fixing); CLI command renames, config schema changes, and new delivery flow steps (Phase 02).

---

These bugs were observed during coding-stats Phases 03 and 04 — the first sustained use of son-of-anton on a real project. All three have caused concrete delivery failures. No new behavior is introduced; this phase makes the current system work as documented.

## Phase Goal

This phase should leave the product in a state where:

- A delivery cycle completes end-to-end without hitting any of the three known CLI failures
- `closeout-stack` runs cleanly after a multi-worktree gated delivery without operator intervention on `state.json`
- Every PR opened via the orchestrator has a title that reflects what the ticket delivers, not how it was tested

## Committed Scope

### `state.json` sync in `advance`

The worktree holds authoritative state; the primary checkout is never updated until closeout. `closeout-stack` reads from the primary and refuses to run when it sees tickets as incomplete. Sync `state.json` from the active worktree back to the primary checkout at the end of each `advance` call.

### PR title derived from ticket content

`openPullRequest` currently passes `readFirstCommitSubject` to `buildPullRequestTitle`. When the first commit is the red test commit (`test(PN.NN): ... [red]`), the PR title becomes that test commit subject. Replace with ticket-content derivation: parse ticket type from the ticket filename or a type field, map to conventional commit prefix, and produce `type(scope): <ticket-derived subject> [PXX.XX]`. Fall back to `feat(scope): <ticket title lowercase> [PXX.XX]` if type is not derivable.

## Explicit Deferrals

- `codex-preflight patched <sha>` guard inversion — command is currently disabled in config and is killed in Phase 02; fix would be immediately superseded
- `post-verify-self-audit` → `post-verify` rename (Phase 02)
- `codex-preflight` → `subagent-code-review` rename (Phase 02)
- `selfAudit` removal from config schema (Phase 02)
- `RESUME COMMAND` guard in generated handoff artifact (Phase 02, code-generated)
- Orchestrator ergonomics: worktree context guard, `status` next-command output, doc-only early failure (Phase 03)

## Exit Condition

Both fixes are in place with tests. `closeout-stack` runs cleanly after a multi-worktree gated delivery without manual `state.json` edits. Every PR opened by the orchestrator has a title in the form `type(scope): <subject> [PXX.XX]`.

## Retrospective

`skip` — targeted bug fixes with no workflow or operator behavior changes.
