# P18.02 Delivery base branch behavior

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- First ticket state uses `deliveryBaseBranch` as `baseBranch`.
- Primary worktree discovery uses `deliveryBaseBranch` rather than `defaultBranch`.
- Restack/rebase for the first ticket targets `origin/<deliveryBaseBranch>`.
- PR creation uses each ticket's delivery base branch, including non-`main` configured bases.
- Status and handoff language reports the configured delivery base branch where applicable.

## Red

- Write a failing delivery-flow test with `defaultBranch: "main"` and `deliveryBaseBranch: "release-next"` proving the first ticket base is `release-next`.
- Write a failing restack/rebase test proving the first ticket rebases onto `origin/release-next`, not `origin/main`.
- Write a failing primary-worktree discovery or status test proving the configured delivery base is named in operator-facing output.
- Run the test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P18.02): honor delivery base branch [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Replace delivery-base uses of `config.defaultBranch` with `config.deliveryBaseBranch`.
- Thread `deliveryBaseBranch` through state sync, ticket start, worktree discovery, restack, rebase, and relevant status formatting dependencies.
- Leave repo-primary references on `defaultBranch` when they are not delivery-base behavior.

## Refactor

- Rename helper parameters from `defaultBranch` to `deliveryBaseBranch` only when the helper truly consumes the delivery base.
- Avoid broad file churn in unrelated review, notification, or CLI parsing code.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- The first delivery branch no longer starts from repo-primary `defaultBranch` unless the config explicitly sets both roles to the same branch.
- Existing stacked ticket behavior still bases later tickets on the previous ticket branch when appropriate.
- GitHub default branch discovery cannot override configured `deliveryBaseBranch`.
- Error and status copy does not keep saying `main` for configured non-`main` delivery bases.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: delivery-base behavior tests should fail before implementation.
Why this path: delivery behavior is the largest branch-role surface and needs a focused PR separate from closeout.
Alternative considered: patching all branch roles in one ticket was rejected as too broad for review.
Deferred: closeout target behavior remains in `P18.04`.
Contract note: none.

Implementation note: first-ticket state sync, primary worktree discovery, and first-ticket restack now consume `deliveryBaseBranch`; `defaultBranch` remains available for repo-primary references such as ticket-file links and later metadata work.
