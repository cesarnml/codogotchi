# Phase 06 Retrospective — soa-sync Refactor: Consumer Upgrade Story

## Scope delivered

Five tickets across PRs [#18](https://github.com/cesarnml/son-of-anton/pull/18), [#19](https://github.com/cesarnml/son-of-anton/pull/19), [#20](https://github.com/cesarnml/son-of-anton/pull/20), [#21](https://github.com/cesarnml/son-of-anton/pull/21), and #22 on branch stack `agents/p6-01-…` through `agents/p6-05-…`:

- **P6.01** — renamed `sync-skills.sh` → `soa-sync.sh`, added migration runner (`SOA_TARGET_VERSION` + `apply_migrations()`), ran `run_migration_1()` to move review artifacts from `.agents/delivery/*/reviews/` to `docs/product/delivery/*/reviews/`, updated all references.
- **P6.02** — moved retrospectives from `notes/public/` to `docs/product/retrospectives/`, updated every path reference in skills, AGENTS.md, and docs.
- **P6.03** — added `AGENTS.soa.md` and `CLAUDE.soa.md` at repo root; implemented `inject_soa_block` in `soa-sync.sh` using `<!-- soa:start/end -->` markers; added two edge-case fixes after subagent review (symlink resolution, malformed-marker guard).
- **P6.04** — updated `README.md` with four new sections (gitignore rationale, injection behavior, migration runner contract, lint-ignore step); fixed stale `sync-skills.sh` references; updated `start-here.md`.
- **P6.05** — this phase-exit and retrospective.

## What went well

**TDD + bash integration fixtures.** Shelling out to `soa-sync.sh` from `git init` temp fixtures gave fast, high-fidelity tests. The test discovered the `set -e` + `|| return` exit-code bug (P6.03) that would have silently broken all P6.01 migration tests in consumer repos — found it before the PR opened.

**Atomic P6.01 scope.** Bundling the rename, migration runner, `run_migration_1`, and all reference updates into a single ticket eliminated a class of "references updated but migration not written" half-states. The grill-me decision to make P6.01 atomic paid off.

**Subagent review depth.** The P6.03 codex subagent found two real edge cases: the `|| return` exit code under `set -e` and the symlink-clobber in `inject_soa_block`. Both required non-obvious fixes. The adversarial framing ("assume the implementation has holes") produced actionable findings, not a checklist of "spec landed."

## Pain points

**Write tool strips executable bit.** `soa-sync.sh` lost its execute permission when written by the AI tool, requiring a follow-up `chmod +x` commit in P6.01 (commit `5792c80`). This is an avoidable waste: a post-`Write` hook or a script that sets permissions after writing would eliminate the extra commit.

**Review artifacts accumulating stale deletions.** Across P6.03, P6.04, and P6.05, each new worktree started with the review artifacts from the previous tickets deleted from the working tree (but tracked in git). The worktree creation process copies git state but the review artifact files were written post-commit in each prior ticket, so they appeared as working-tree deletions. Required `git checkout HEAD -- ...` at the start of each ticket. Root cause: review artifacts written by the orchestrator CLI are not committed as part of the ticket's green commit — they're committed on the advance boundary. This is expected orchestrator behavior, but the pattern recurred in every ticket.

**Qodo free-tier billing noise.** All four PRs triggered a Qodo "You've reached your monthly free-tier limit" comment that the `poll-review` escalated as `needs_patch`. Triaging this as `clean` is correct but requires a manual judgment call each time. Either upgrading Qodo or switching the poll-review vendor list to exclude Qodo would eliminate the recurring noise.

## Surprises

**`|| return` exit code propagates under `set -e`.** In `inject_soa_block`, `[ -f "$source_path" ] || return` caused the whole script to exit with code 1 when the source file was absent, because `return` inherits the exit code of the failed `[ -f ]` test. With `set -e` active, the caller sees a non-zero exit. Fixed with `|| return 0`. This is a subtle bash footgun: `||` prevents `set -e` from catching the left side's failure, but the `return` still propagates the failure code unless explicitly zeroed.

**`AGENTS.soa.md` and `CLAUDE.soa.md` have near-identical content.** The two files differ only in framing (Claude-imperative vs. AGENTS.md-declarative), but the actual rule content is 90%+ overlapping. The grill-me session flagged this as a potential maintenance burden and deferred a DRY approach. The decision to keep them separate was correct for P6: the format requirements of AGENTS.md vs. CLAUDE.md are different enough that a single source template would need nontrivial transformation logic. Deferred to a future phase if the content diverges more.

**Migration idempotency needed explicit guard.** `run_migration_1` uses `git mv`, which fails if the source path doesn't exist. The `[ -d "$reviews_dir" ]` guard makes it idempotent, but the guard was not obvious from the spec — it emerged from test fixture design (the second-run fixture would fail without it).

## What we'd do differently

**Add a post-Write executable-restore step.** The `soa-sync.sh` permission loss could be avoided by tracking files that must be executable and restoring permissions after the Write tool runs. A `scripts/` convention (all `*.sh` files are executable) would be enforceable by a post-commit hook or a verify step.

**Commit review artifacts in the same commit as the green implementation, not on advance.** The worktree deletion pattern suggests the orchestrator should stage review artifacts into the commit that closes a ticket rather than writing them to disk on advance. This would make each worktree start from a clean state without manual `git checkout HEAD --` recovery.

**Warn-not-patch policy for linters.** The lint-ignore step (P6.04) was documented rather than automated because the correct ignore location depends on the consumer's toolchain. The `soa-sync.sh` already prints a reminder; documenting this in README and treating it as a user action (rather than trying to detect and auto-patch) is the right call. Future versions could offer a `--lint-ignore` flag to `soa-sync.sh` that patches the most common cases.

## Net assessment

Phase 06 delivered its stated goal: `soa update` followed by `bun run sync` now produces a fully upgraded consumer repo — skills symlinked, agent rules injected into `AGENTS.md`/`CLAUDE.md`, `.soa-sync-version` written, and a lint-ignore reminder printed. The migration runner contract is documented and tested. All five product contract items from the phase plan shipped.

## Follow-up

- Consider adding a `--lint-ignore` flag to `soa-sync.sh` to auto-patch `.prettierignore` and `.eslintignore` for common toolchains.
- Investigate whether review artifacts can be committed atomically with the advance step to prevent the worktree-deletion pattern from recurring.
- Add a post-`Write` executable check to the delivery workflow for shell scripts.
- Upgrade or configure out Qodo free-tier billing notifications to reduce `poll-review` noise.

---

_Created: 2026-05-09. PRs #18–#22 open (stack not yet merged — awaiting developer closeout)._
