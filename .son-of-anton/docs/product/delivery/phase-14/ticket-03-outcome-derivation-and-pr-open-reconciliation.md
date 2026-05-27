# P14.03 Outcome derivation and PR-open reconciliation

Size: 4 points
Type: feat
Scope: subagent-review
Red: required

## Outcome

- A new orchestrator step `reconcile-subagent-review` runs between the existing `subagent-review` step and `open-pr`. It observes git state since the row's `reviewedHeadSha` and reconciles the ledger against actual git history.
- When a commit subject between `reviewedHeadSha` and HEAD contains `[subagent-review]` and the commit touches files in the reviewed paths, the orchestrator appends a `patched` ledger row referencing the commit SHA in `patches: [<sha>]`.
- A new CLI affordance `bun run deliver subagent-review record-deferred --reason "<rationale>"` appends a `deferred` ledger row with the rationale captured in a `reason` field. The rationale is required (empty string → error).
- The reconciliation step hard-blocks PR open on two silent-lie conditions:
  - **Condition A:** files in the reviewed paths were modified since `reviewedHeadSha` but no `[subagent-review]`-labeled commit touches them, AND no `deferred` row exists for this review.
  - **Condition B:** the report contains actionable findings (`Actionable findings` section non-empty, not `None.`) and no commit modified reviewed paths AND no `deferred` row exists.
- A new flag `--ack-reconciliation <patched|deferred|clean>` resolves either silent-lie condition:
  - `--ack-reconciliation patched --commit <sha>`: appends a `patched` row referencing the operator-provided SHA (used when a labeled commit exists under a different convention, or when squash-merge collapsed the SHA).
  - `--ack-reconciliation deferred --reason "<rationale>"`: same effect as `record-deferred`.
  - `--ack-reconciliation clean --reason "<rationale>"`: appends a `clean` row with `acknowledgment: "operator-confirmed-clean"` and the reason; used for unrelated post-review modifications or operator-judged non-issues.
- On hard-block, the orchestrator exits non-zero with a message naming the condition that fired and the three resolution paths. The message format is stable and documented (so headless integrations can parse it).
- **Green test target:** `bun test tools/delivery/test/reconciliation.test.ts` (new) covers: `[subagent-review]` commit auto-detection appends a `patched` row; `record-deferred` appends a `deferred` row with the reason; Condition A hard-blocks with the documented message; Condition B hard-blocks; each of the three `--ack-reconciliation` variants resolves the corresponding condition; absent `--reason` on `record-deferred` errors.
- **Manual demo command:** in a fixture ticket worktree, (1) run subagent-review and observe a `clean` row; (2) make a code change that touches a reviewed file under a non-labeled commit; (3) run `bun run deliver open-pr` and observe non-zero exit with the documented Condition A message; (4) amend the commit subject to add `[subagent-review]`; (5) re-run `open-pr` and observe a `patched` row appears and PR open proceeds.

## Red

- Add tests in `tools/delivery/test/reconciliation.test.ts`:
  - `detectLabeledCommit`: given a worktree with a `[subagent-review]`-prefixed commit touching reviewed paths between `reviewedHeadSha` and HEAD → returns the commit SHA.
  - `detectLabeledCommit`: given a worktree with no such commit but with file modifications → returns `null`.
  - `reconcileReview`: Condition A (modifications without label, no deferred row) → throws `ReconciliationBlockedError` with `condition: 'A'` and the documented message.
  - `reconcileReview`: Condition B (actionable findings, no commit, no deferred row) → throws with `condition: 'B'`.
  - `reconcileReview`: with a labeled commit → returns silently and appends a `patched` row.
  - `recordDeferred`: empty `--reason` → throws.
  - `recordDeferred`: valid reason → appends `deferred` row with reason captured.
  - `--ack-reconciliation patched --commit <sha>`: appends `patched` row with the operator-provided SHA.
  - `--ack-reconciliation deferred --reason "X"`: appends `deferred` row.
  - `--ack-reconciliation clean --reason "X"`: appends `clean` row with `acknowledgment: "operator-confirmed-clean"`.
- Run `bun test`; confirm all fail.
- Commit: `test(P14.03): outcome derivation and PR-open reconciliation [red]`

## Green

- Implement `detectLabeledCommit(headSha, reviewedHeadSha, reviewedPaths)` using `git log --grep` scoped to the SHA range.
- Implement `reconcileReview(ledger, report, gitState)` that:
  - Inspects whether any commit between `reviewedHeadSha` and HEAD has `[subagent-review]` in its subject AND touches reviewed paths.
  - Inspects whether actionable findings exist in the report (parses the `Actionable findings` section; empty / `None.` → no findings).
  - Inspects whether a `deferred` row already exists for this review SHA.
  - Returns `'patched'` (with SHA) when a labeled commit exists.
  - Throws `ReconciliationBlockedError` with `condition` and the documented message string for the two silent-lie conditions.
  - Returns `'clean'` when neither finding nor modification is present.
- Implement `bun run deliver subagent-review record-deferred --reason "<text>"` as a subcommand that validates the reason is non-empty and appends a `deferred` ledger row.
- Implement `--ack-reconciliation <variant> --commit <sha> --reason "<text>"` flag parsing on the `open-pr` step. Each variant appends a ledger row of the matching outcome.
- Wire `reconcile-subagent-review` into the orchestrator step list (between `subagent-review` and `open-pr`) per `orchestrator.config.json`.
- Run `bun test`; confirm green.
- Commit: `feat(P14.03): reconcile-subagent-review step blocks silent-lie PR opens`

## Refactor

- Consolidate the three `--ack-reconciliation` variants into a single `recordAcknowledgment(variant, options)` function if the implementation diverged across variants.
- Extract the documented error message into a constant so the format is testable and stable.

## Review Focus

- **Stable error message format.** Headless integrations (CI, alerts) will parse the hard-block message. Verify the format is documented in code (constant + comment) and tested against an exact string match.
- **`reviewedPaths` extraction.** What constitutes a "reviewed path"? Read from the prompt's "Files touched" section, or computed independently from the diff at review time? Source of truth matters — drift here produces false positives/negatives in reconciliation.
- **Squash-merge handling.** P14.03's pitfall PF5 (stacked-PR squash collapses the labeled commit) requires `--ack-reconciliation patched --commit <new-sha>` to work even when the SHA was not in the original `reviewedHeadSha..HEAD` range. Verify the variant accepts arbitrary SHAs without re-running `detectLabeledCommit`.
- **Multi-commit reconciliation.** If two `[subagent-review]` commits exist in the range, does the row record both SHAs in `patches: [<sha1>, <sha2>]`? Verify the implementation enumerates rather than picking the last.
- **Condition B sensitivity.** The check for "actionable findings exist" parses report markdown. Verify the parser tolerates minor format variations (extra blank lines, trailing whitespace, slight section-heading drift) without falsely reporting findings absent.
- **Empty-reason rejection.** Both `record-deferred --reason ""` and `--ack-reconciliation deferred --reason "    "` (whitespace) must reject. Otherwise the audit-trail intent of the reason field is defeated.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: 20-test `reconciliation.test.ts` covering `detectLabeledCommits`, `parseActionableFindings`, `reconcileReview` (clean / patched / Condition A / Condition B / deferred-row bypass), `recordDeferred` (valid / empty / whitespace), and `recordAcknowledgment` (patched / deferred / clean variants plus their required-field rejection).

Why this path:

- All reconciliation logic lives in pure helpers under `tools/delivery/reconciliation.ts` with dependency-injected git adapters so tests don't touch a real git repo. The CLI `cli-runner.ts` glue supplies the real adapters via `spawnSync`-backed thunks (`gitListChangedPaths`, `gitListCommitsInRange`, `gitListCommitFiles`).
- Stable error-message strings are exported as `RECONCILIATION_BLOCKED_MESSAGE_A` and `RECONCILIATION_BLOCKED_MESSAGE_B` constants. Headless integrations match against the prefix (`reconcile-subagent-review: Condition A —` / `— Condition B —`). Tests assert the exact constant.
- `reviewedPaths` is derived at gate time from `git diff --name-only <baseBranch>..<reviewedHeadSha>`. That choice avoids adding new state and stays computationally cheap. The alternative of parsing the prompt's "Files touched" section was rejected because the prompt text is operator-authored and drift between the prompt prose and the actual diff would produce false negatives in the gate.
- Multi-commit reconciliation works: `detectLabeledCommits` enumerates every `[subagent-review]`-labeled commit in range whose change-set intersects `reviewedPaths` and returns the full SHA array. The appended `patched` row carries all of them in `patches: [...]`.
- `--ack-reconciliation patched --commit <sha>` accepts arbitrary operator-provided SHAs without re-running `detectLabeledCommits`. This handles squash-merge collapsing of the labeled commit (PF5).
- `record-deferred` rejects empty and whitespace-only reasons so the audit trail intent of the field cannot be defeated by passing `""` or `"   "`.

Alternative considered: making `reconcile-subagent-review` a hidden internal step driven only by `open-pr`. Rejected because the ticket explicitly defines it as a separately invokable command — operators benefit from being able to run the gate alone for diagnostics before the publish-time invocation.

Deferred: structured findings parsing beyond the `Actionable findings` section detector. The current implementation only asks "are there actionable findings? yes/no" — it does not extract per-finding identity for individual patch mapping. The phase 14 product plan explicitly defers structured findings parsing.

Contract note: `reconcile-subagent-review` is gated inside `open-pr` as well (calling `runReconciliationGate` before publish), so the operator can either run the explicit step or let `open-pr` perform it implicitly. Status transitions are unchanged — a patched row appended by reconciliation does not alter `subagentReviewOutcome` on the ticket state; the row count in the artifact is the authoritative audit trail.
