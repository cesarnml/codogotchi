# P16.03 Add Post-Phase Advisory Observations Triage Command

Size: 5 points
Type: feat
Scope: delivery
Red: required

## Outcome

- `bun run deliver --plan <plan-path> triage-advisory-observations` scans the selected phase's subagent-review reports.
- The command groups advisory observations by ticket and source report.
- The command writes or updates the advisory-observation triage artifact using the schema from P16.02.
- The command is post-phase and decision-recording only; it never applies source patches.
- The command supports explicit disposition input without requiring an interactive terminal.

## Red

- Add CLI tests that fail until the command exists:
  - Usage lists `triage-advisory-observations`.
  - A fixture phase with advisory observations produces a grouped triage artifact.
  - `Actionable findings` remain outside the advisory-observation disposition path.
  - Running the command without required disposition data exits with a clear message rather than guessing.
  - Re-running with the same decisions is idempotent.
- Commit with suffix `[red]`: `test(P16.03): add advisory observations triage command [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add CLI parsing and dispatch for `triage-advisory-observations`.
- Resolve the phase's reviews directory from the plan path and delivery state/artifacts.
- Read `*-subagent-review.ledger.json` and `*-subagent-review.report.md` sidecars, then feed parsed observations into the disposition artifact writer.
- Accept disposition data via flags or an explicit input file; do not rely on an interactive prompt.

## Refactor

- Keep command orchestration in `cli-runner.ts` thin; put scanning and artifact logic in focused helper modules.
- Avoid changing existing subagent-review runner invocation or reconciliation flows.

## Review Focus

- Verify the command can run after phase closeout from `main`.
- Verify it records decisions and does not modify implementation files.
- Verify command naming remains `triage-advisory-observations` at both the delivery CLI layer and the `/soa triage-advisory-observations phase-XX` wrapper layer.
- Verify idempotency and error messages are suitable for headless use.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `bun test ./tools/delivery/test/p16-03.test.ts` failed because `../advisory-observation-command` did not exist.
Why this path: add a focused command helper that scans subagent-review ledger/report sidecars, matches parsed `Advisory Observations` to explicit disposition input, and writes the phase-level triage artifact without touching source files.
Alternative considered: extending the existing PR review triage flow was rejected because Phase 16 explicitly scopes this to post-phase subagent-review advisory observations, not external AI review findings.
Deferred: warning on untriaged or suspicious advisory-observation evidence remains in P16.04.
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
