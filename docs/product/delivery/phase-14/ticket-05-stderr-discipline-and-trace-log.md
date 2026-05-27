# P14.05 Stderr discipline and trace log

Size: 2 points
Type: feat
Scope: subagent-review
Red: required

## Outcome

- The runner step persists only the model's final report text in `*-subagent-review.report.md`. Stderr from the runner subprocess is **not** included in the persisted report.
- A sibling file `*-subagent-review.trace.log` is written to the same worktree directory containing the full stderr capture. The trace file is local-only — added to the orchestrator's gitignore template so it never enters git history or PR diffs.
- The trace's lifetime is bounded by the worktree. After `closeout-stack` or any worktree cleanup, the trace evaporates with the worktree. No persistence to git, no archival to remote storage.
- For codex-cli runs, the `runnerStatus` self-report line that the model emits in its report body is preserved (it's part of the model's stdout, not stderr). Only the runner-process stderr stream is stripped.
- **Green test target:** `bun test tools/delivery/test/subagent-runner.test.ts` (extended) covers: a runner invocation whose stderr contains 1000+ lines of noise produces a `report.md` whose content matches the model's stdout exactly (no stderr admixture); a `trace.log` file is written alongside the report containing the stderr; the gitignore template at `docs/template/stubs/.gitignore` (or equivalent) contains a pattern matching `*-subagent-review.trace.log`.
- **Manual demo command:** run an end-to-end ticket through the orchestrator using codex-cli (which emits substantial stderr in normal operation). Inspect:
  - `docs/product/delivery/<plan>/reviews/<ticket>-subagent-review.report.md` — must contain only the model's final report (no `stderr:` section, no PostToolUse hook noise, no Codex config block).
  - `docs/product/delivery/<plan>/reviews/<ticket>-subagent-review.trace.log` — exists in the worktree, contains the stderr capture, is ignored by `git status`.
  - `git status` in the worktree — must not list `*-subagent-review.trace.log` as a tracked or untracked-but-discoverable file (it's gitignored).

## Red

- Add tests in `tools/delivery/test/subagent-runner.test.ts`:
  - `persistReport`: given a runner result with `stdout: "<report content>"` and `stderr: "<noise>"` → the written `report.md` content equals `<report content>` (no stderr present).
  - `persistTrace`: given the same runner result → a `trace.log` file is written to the same directory containing `<noise>`.
  - `gitignoreTemplate`: read `docs/template/stubs/.gitignore` (or the canonical gitignore template path); assert it contains `*-subagent-review.trace.log` (or a glob matching it).
- Run `bun test`; confirm all fail.
- Commit: `test(P14.05): stderr stripped from report; trace.log written locally and gitignored [red]`

## Green

- Update `persistReportFromRunnerResult` (or the equivalent writer function) in `tools/delivery/subagent-runner.ts`:
  - Write `result.stdout` (or just the model's final report text) to `report.md`.
  - Write `result.stderr` to a sibling `trace.log` in the same directory.
  - Do not embed stderr in the report.
- Update the gitignore template at `docs/template/stubs/.gitignore` (or wherever the canonical template lives) to include `*-subagent-review.trace.log`.
- Update `scripts/soa-sync.sh` if it copies the gitignore template to consumer repos — verify the new pattern lands.
- Run `bun test`; confirm green.
- Commit: `feat(P14.05): strip stderr from report; emit gitignored trace.log sibling`

## Refactor

- If `persistReport` and a new `persistTrace` share file-path composition, extract a single `subagentReviewArtifactPaths` helper (post-P14.04 this helper likely already exists; reuse it).

## Review Focus

- **Stdout vs report-body distinction.** For claude-cli runs, the model's final report IS its stdout. For codex-cli, the model's final report is the `codex` section in the stdout, but there's also session-config preamble. Verify the writer captures only the model's final report body, not the full stdout. If the writer naively persists `stdout` it may include preamble noise.
- **Trace file path collision.** If a consumer repo had a pre-existing file named `*-subagent-review.trace.log` (unlikely but possible), the writer must overwrite or warn. Verify the write is unconditional overwrite (the trace is ephemeral).
- **Gitignore template propagation.** Consumer repos pull the gitignore template via `/soa update` → `soa-sync.sh`. Verify the new gitignore pattern actually propagates to consumer-repo `.gitignore` files on update, not just lands in the SoA template.
- **Edge case: empty stderr.** When the runner produces zero stderr (rare but possible), is an empty `trace.log` still written, or is the file omitted? Either is acceptable — verify the choice is consistent and documented.
- **What was intentionally deferred:** the prompt prologue reorder, doc/skill alignment, and retrospective land in P14.06. This ticket ships only the behavioral mechanism for stderr/trace handling.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `bun test tools/delivery/test/subagent-runner.test.ts` failed because `report.md` still contained a combined `stdout:`/`stderr:` body, no sibling `trace.log` was written, and the repo ignore surface lacked `*-subagent-review.trace.log`.
Why this path: `writeSubagentReviewOutcome` now writes stdout as the durable report, writes stderr to a sibling trace log, and returns both paths while keeping the ledger `rawOutput` pointed at the report. `tryRunner` carries stdout/stderr alongside the legacy formatted raw output so callers can persist the streams separately without changing classification behavior.
Alternative considered: embedding the trace path in the ledger was rejected because the trace is explicitly local-only and gitignored; persisting a path in committed JSON would imply a durable artifact contract that this ticket intentionally avoids.
Deferred: no archival of trace logs beyond the active worktree; no broader prompt/report content changes beyond excluding generated prompt/report artifacts from Prettier's source-formatting surface.
Contract note: root `.gitignore` is the canonical ignore template in this repo; `scripts/soa-sync.sh` now appends the trace-log pattern for consumer repos during `/soa update`.

Follow-up after codex-platform demo: the first P14.05 codex-cli run proved this belongs in the same ticket, not a separate gate rewrite. The gate already has the right state model (`runnerKind`, `terminatedReason`, stdout/stderr sidecars); the bug was two contained Codex integration details. First, `codex exec` can echo the prompt/source code into stderr, so regex-scanning all stderr for rate-limit tokens misclassified source text as an authentic rate-limit. The classifier now only treats JSON-shaped structured rate-limit payloads (or exit code 7) as authentic for codex-cli. Second, codex-cli supports `--output-last-message`; the orchestrator now uses a temp last-message file so `report.md` gets the final model report while stderr remains the local trace. The skipped-run log message was also narrowed so a runner that actually ran but terminated non-cleanly is not described as “all runners unavailable.”
