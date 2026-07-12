# P19.01 Review-gap scaffold sync

Size: 3 points
Type: feat
Scope: sync
Red: required

## Outcome

- `docs/template/review-gaps/README.md`, `ledger.jsonl`, and `promotion-queue.md` define the consumer scaffold for post-phase review-gap capture.
- `scripts/soa-sync.sh` creates `docs/product/review-gaps/` in consumer repos when missing.
- Sync is idempotent and does not overwrite existing consumer README, ledger, or promotion queue content.
- Tests prove fresh consumer sync creates the scaffold and reruns preserve existing review-gap files.

## Red

- Write a failing sync test that runs `soa-sync.sh` in a consumer fixture and expects `docs/product/review-gaps/README.md`, `ledger.jsonl`, and `promotion-queue.md` to exist.
- Write a failing sync test that pre-populates at least one review-gap file, reruns sync, and proves the file content is preserved.
- Run the targeted sync tests and confirm they fail before implementation.
- Commit with suffix `[red]`: `test(P19.01): cover review-gap scaffold sync [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Add the template scaffold under `docs/template/review-gaps/`.
- Update `soa-sync.sh` to copy the scaffold into `docs/product/review-gaps/` only when each destination file is absent.
- Keep source-repo mode behavior unchanged except for normal skill relinking.
- Make the targeted sync tests pass.

## Refactor

- Keep scaffold-copying logic small and local to `soa-sync.sh`.
- Avoid introducing a migration version unless tracked files must move or existing consumer files need structural mutation.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Verify existing consumer `docs/product/review-gaps/ledger.jsonl` content cannot be overwritten by sync.
- Verify the scaffold text matches the Phase 19 vocabulary without trying to implement the full QC workflow early.
- Verify template paths are source-repo paths and destination paths are consumer-repo paths.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: sync tests should fail because no review-gap scaffold is copied today.
Why this path: scaffold sync is the smallest stable foundation for later QC recording.
Alternative considered: create the scaffold only when `/soa quality-control` first runs; rejected because the issue requires fresh consumers to receive the artifact home after sync.
Deferred: ledger validation and skill flow belong to later tickets.
Contract note: none.
