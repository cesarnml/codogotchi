# P18.03 PR metadata and state repair branch roles

Size: 2 points
Type: feat
Scope: delivery
Red: required

## Outcome

- PR body ticket-file links use repo-primary `defaultBranch`.
- PR body stacked-base metadata uses the ticket's actual `baseBranch`.
- State repair and sync paths preserve configured delivery bases instead of reintroducing `defaultBranch` as the delivery base.
- Operator-facing metadata distinguishes repo-primary references from delivery-base branch references.

## Red

- Write a failing PR metadata test with `defaultBranch: "main"` and ticket `baseBranch: "release-next"` proving ticket-file links point at `main` while stacked-base metadata says `release-next`.
- Write a failing state repair or sync test proving a repaired first ticket keeps `deliveryBaseBranch`, not `defaultBranch`.
- Run the test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P18.03): separate metadata branch roles [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Audit PR body builders, stack metadata helpers, state inference, and repair code for branch-role usage.
- Keep `githubRepo.defaultBranch` semantics for repo-primary documentation links.
- Ensure delivery-base fields are read from ticket state or `deliveryBaseBranch`, never from GitHub default branch discovery.

## Refactor

- Rename local variables only where it prevents future branch-role confusion.
- Keep PR metadata formatting stable except for corrected branch-role values.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Ticket file links and stacked base branch metadata intentionally point at different branches when configured roles differ.
- State repair cannot silently reset a configured delivery base back to repo-primary `defaultBranch`.
- GitHub-derived `defaultBranchRef` is only used for repo-primary metadata, not delivery-base behavior.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: metadata and state repair tests should fail before implementation.
Why this path: metadata and repair are easy to regress after delivery-base plumbing, so they get their own focused slice.
Alternative considered: folding this into `P18.02` was rejected because PR metadata has a different branch-role contract than delivery-base execution.
Deferred: closeout output and branch guards remain in `P18.04`.
Contract note: none.

Implementation note: existing PR refresh now sends the ticket `baseBranch` to GitHub alongside the refreshed title/body so GitHub PR metadata, stacked-base body metadata, and delivery state cannot drift when repo-primary `defaultBranch` differs from the delivery base.
