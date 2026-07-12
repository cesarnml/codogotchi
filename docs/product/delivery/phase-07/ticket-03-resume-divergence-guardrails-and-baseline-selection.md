# P7.03 Resume divergence guardrails and baseline selection

Size: 5 points
Type: feat
Scope: delivery-resume

## Outcome

- Resume detects divergence between persisted `runPolicy` and current repo policy on only the bounded Phase 07 fields.
- Resume refuses to continue silently on divergence unless the operator explicitly selects `--baseline=orchestrator` or `--baseline=run-policy`.
- Baseline selection plus optional overrides resolves a new active `runPolicy` and persists it back to `state.json`.

## Red

- Write failing tests for divergence detection limited to the four approved Phase 07 policy fields.
- Write failing tests for refusal behavior when divergence exists and no baseline is passed.
- Write failing tests for baseline selection plus explicit overrides persisting a new resolved `runPolicy`.
- Run the targeted test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P7.03): cover resume run-policy divergence rules [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Implement divergence comparison for `ticketBoundaryMode`, `reviewPolicy.subagentReview`, `reviewPolicy.prReview`, and tagged `reviewSubagent`.
- Add `--baseline <orchestrator|run-policy>` handling for resume-time recovery.
- Persist the resolved post-baseline run policy when resume continues.

## Refactor

- Extract comparison and recovery-command formatting helpers if resume logic becomes difficult to audit inline.
- Keep resume-specific refusal logic separate from execute-time resolution rules where possible.

## Review Focus

- Whether divergence detection is strictly scoped and does not expand into full-config drift blocking.
- Whether refusal text includes both policies and exact recovery commands.
- Whether `--baseline=orchestrator` with no extra overrides correctly adopts current repo defaults and continues.
- Deferred: final docs and retrospective content stay out of this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `patchRunPolicyWithFlags`, `detectRunPolicyDivergence`, and `formatRunPolicyDivergenceError` missing from `state.ts` caused import failure at test load time; `baseline` field missing from `ParsedCliArgs` caused type errors.

Why this path: Three pure helpers in `state.ts` (`detectRunPolicyDivergence`, `formatRunPolicyDivergenceError`, `patchRunPolicyWithFlags`) keep all divergence logic independently testable. The `loadState` wrapper in `cli-runner.ts` returns `{ state, hadPersistedRunPolicy }` so the divergence check can distinguish a fresh-start (normalization-derived) runPolicy from one that was already persisted — only the latter triggers the divergence refusal. The check is inserted immediately after `loadState` and before the command switch, allowing a narrow exemption list (`status`, `sync`, `repair-state`, `record-review`, `reconcile-late-review`) for idempotent/diagnostic commands that do not consume policy.

Alternative considered: Storing a `runPolicySource: 'persisted' | 'derived'` discriminant in `state.json` — rejected because it adds persistent state for a transient concern; `hadPersistedRunPolicy` in the load result is sufficient and disappears after the check.

Deferred: Run-policy observability (printing active runPolicy in `status` output) and docs updates stay in P7.04 and P7.05. Subagent also flagged that `startTicket`, `recordPostVerify`, and `applyAdvanceBoundaryMode` still read from `context.config` rather than `state.runPolicy` — plumbing the persisted policy through to actual consumers is intentionally deferred to P7.04 which owns policy observability.

Contract note: none; `Type: feat` and `Scope: delivery-resume` are accurate.
