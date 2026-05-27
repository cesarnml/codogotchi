# P13.02 Add write-subagent-adversarial-review prompt step

Size: 5 points
Type: feat
Scope: delivery
Red: required

## Outcome

- The orchestrator exposes a `write-subagent-adversarial-review [ticket-id]` command.
- The command records a filled subagent adversarial review prompt before `subagent-review` can invoke a runner for a code ticket.
- The prompt artifact is deterministic, ticket-scoped, and persisted under the phase delivery artifacts.
- Status/next-command rendering sends verified code tickets to `write-subagent-adversarial-review` before `subagent-review`.
- The prompt-writing step makes clear that the primary agent authors the brief for a subagent; it does not perform the adversarial review.

## Red

- Add failing ticket-flow/status coverage showing a verified code ticket's next command is `write-subagent-adversarial-review` when `subagentReview` is enabled and no prompt has been written.
- Add failing CLI parsing/usage coverage for `write-subagent-adversarial-review`.
- Add failing state/artifact coverage proving `subagent-review --preferred-runner ...` refuses to run when the prompt artifact is missing for a code ticket.
- Add failing coverage proving doc-only tickets still skip according to `skip_doc_only` policy and do not require prompt authoring.
- Run the targeted tests and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P13.02): cover subagent adversarial prompt step [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Add the command dispatch, parser surface, usage text, and status next-command rendering for `write-subagent-adversarial-review`.
- Persist a filled-prompt artifact path in state or an equivalent ticket-scoped marker before runner invocation. Keep the state addition as narrow as possible.
- Provide the command with enough deterministic prompt content for the primary agent to write the filled template. If the implementation cannot safely auto-fill all sections, it must still persist the primary-authored prompt and fail closed when the content is missing or placeholder-like.
- Gate runner invocation on the prompt artifact for code tickets when `subagentReview` is not disabled.
- Keep `subagent-review` as the runner command and keep the existing `subagentReview` policy vocabulary.

## Refactor

- Prefer a small prompt-artifact helper over embedding file-path logic directly in the command switch.
- Keep prompt-state naming aligned with the existing `subagentReview*` vocabulary.
- Do not move the runner invocation logic in this ticket unless needed to read the prompt path.

## Review Focus

- Verify command ordering: `verified` -> `write-subagent-adversarial-review` -> `subagent-review` -> `open-pr`.
- Verify prompt-writing cannot be skipped for code tickets under `required` or `skip_doc_only`.
- Verify doc-only behavior remains structurally skipped under `skip_doc_only`.
- Verify the prompt artifact path is deterministic and survives state save/load/sync.
- Verify error messages tell the operator to write the subagent adversarial prompt rather than asking the primary agent to review its own work.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: status and gate tests should fail because the command and prompt marker do not exist yet.
Why this path: split prompt authoring from runner invocation without renaming the established `subagent-review` gate.
Alternative considered: rename the runner command to `subagent-adversarial-review`, rejected to avoid policy and config churn.
Deferred: consuming the prompt in the runner and advisory-only no-write enforcement.
Contract note: the primary agent writes the adversarial brief; the subagent performs the adversarial review.

### Implementation notes (P13.02)

- Added `write-subagent-adversarial-review [ticket-id] [--prompt-file <path>]` as a new CLI command. It auto-derives a baseline prompt from the ticket spec and changed-files list when no `--prompt-file` is supplied, persists the prompt to `<reviewsDir>/<ticketId>-subagent-adversarial-prompt.md`, and stamps `subagentAdversarialPromptPath` / `subagentAdversarialPromptWrittenAt` onto the ticket state. The prompt artifact is committed and pushed using the same `commitDeliveryArtifactAndPush` helper as the subagent runner artifact.
- A new module `tools/delivery/subagent-prompt.ts` owns the deterministic path derivation, the content validator (rejects empty, short, or template-placeholder-like content), the writer, and the runner-gate helper `assertSubagentAdversarialPromptPresent`.
- `subagent-review` now invokes the gate after the doc-only auto-skip and before runner dispatch. The gate is a no-op when `subagentReview` is `"disabled"` or when the ticket is a doc-only auto-skip under `"skip_doc_only"`, so the existing skip semantics are preserved.
- `resolveNextCommand` accepts an optional ticket projection. For `verified` tickets it routes to `write-subagent-adversarial-review` first, falls back to `subagent-review` once the prompt is recorded, and stays on `subagent-review` for doc-only tickets where post-verify already recorded `verifyOutcome=skipped`. The legacy two-arg call (no ticket) defaults to `write-subagent-adversarial-review` so older operator paths still drive the prompt step before the runner.
- `status` now surfaces a `subagent_adversarial_prompt=written at <iso> (<path>)` line whenever the prompt artifact is recorded.

Deferred (consistent with the phase plan):

- Runner does not yet consume the recorded prompt — that lands in P13.03.
- Advisory-only no-write subagent enforcement lands in P13.03.
- Docs/skills/template alignment lands in P13.04.
