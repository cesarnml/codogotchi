# P18.05 Docs and retrospective

Size: 2 points
Type: docs
Scope: docs
Red: skip

## Outcome

- README explains `defaultBranch`, `deliveryBaseBranch`, and `closeoutBranch`.
- `docs/template/overview/start-here.md` explains configured branch-role workflows and the manual promotion boundary.
- `docs/template/delivery/delivery-orchestrator.md` uses branch-role terminology instead of assuming `main`.
- Config examples include all required branch-role fields.
- The Phase 18 retrospective artifact exists at `docs/product/retrospectives/phase-18-configured-branch-targets-retrospective.md`.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**
- No failing automated test is required for this doc-only ticket.

## Green

- Update operator docs with all-`main`, `main` to `staging`, and `release-next` workflow examples.
- Document that `/soa update` migrates existing configs by filling new branch roles from the previous `defaultBranch` value.
- Document that promotion between configured branches remains manual and outside SoA closeout.
- Write the retrospective using the Phase 18 product-plan rationale and final implementation notes.

## Refactor

- Keep docs concise and avoid repeating the full branch-role explanation in every file.
- Remove stale wording that says delivery or closeout always targets `main`.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Docs make the three branch roles distinct without implying automated promotion.
- Examples cover non-`main` and split closeout targets.
- Retrospective captures what operators learned from making branch roles explicit.
- No docs tell agents to bypass the orchestrator path.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: skipped because this is a doc-only ticket.
Why this path: documentation lands after behavior so examples match the shipped config contract.
Alternative considered: spreading docs across behavior tickets was rejected because the final terminology should reflect all branch-role changes together.
Deferred: release-promotion docs beyond the manual boundary.
Contract note: `Red: skip` is intentional for doc-only work.

Implementation note: operator docs now describe separate repo-primary,
delivery-base, and closeout-target branch roles, including all-`main`, staging,
and `release-next` examples. Closeout documentation no longer says the stack
always lands on `main`; it names the configured `closeoutBranch` and keeps
branch promotion outside SoA.
