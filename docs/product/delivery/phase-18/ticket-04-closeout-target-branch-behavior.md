# P18.04 Closeout target branch behavior

Size: 3 points
Type: feat
Scope: closeout
Red: required

## Outcome

- `closeout-stack` requires the operator to run from `closeoutBranch`.
- Closeout fetches, resets, squash-merges or cherry-picks, pushes, and comments against `closeoutBranch`.
- Closeout operator-facing errors and summaries name the resolved closeout target branch.
- Tests cover `defaultBranch: "main"`, `deliveryBaseBranch: "release-next"`, and `closeoutBranch: "staging"`.
- Tests cover migrated non-`main` targets such as `master`.

## Red

- Write a failing closeout test proving the branch guard expects `staging` when `closeoutBranch: "staging"`.
- Write a failing closeout command-sequence test proving fetch/reset/push use `origin/staging` and `staging`, not `main`.
- Write a failing closeout comment or summary test proving PR close messaging names `staging`.
- Run the test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P18.04): honor closeout target branch [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Thread `closeoutBranch` through `closeout-stack` branch guards, fetch/reset commands, merge recovery, push target, PR close comments, and summaries.
- Keep delivery-base branch behavior out of closeout except where ticket state describes the already-delivered stack.
- Ensure error messages do not mention hardcoded `main` or overloaded `defaultBranch` for closeout target expectations.

## Refactor

- Rename closeout helper parameters from `defaultBranch` to `closeoutBranch` where appropriate.
- Keep closeout artifact handling behavior unchanged unless it currently assumes the wrong target branch.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Closeout can land to a branch independent of both GitHub's repository default and the delivery base.
- Existing all-`main` configs remain behaviorally unchanged after migration.
- Non-`main` migrated targets, including `master`, are treated as normal.
- Closeout-owned artifact reconciliation uses the same target branch named in command output.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: closeout target tests should fail before implementation.
Why this path: closeout mutates branches and pushes, so it needs a separate high-scrutiny PR.
Alternative considered: sharing delivery-base as implicit closeout fallback was rejected because `closeoutBranch` is required.
Deferred: automated promotion after closeout is outside Phase 18.
Contract note: none.

Implementation note: closeout-owned branch guard text, fetch/reset/push command
construction, merge-conflict reset recovery, and PR close comments now consume
`closeoutBranch`; repo-primary `defaultBranch` remains out of closeout landing
behavior.

Subagent-review patch: closeout summaries now include
`closeout_target=<closeoutBranch>` so operator-facing completion output names
the resolved closeout target branch.
