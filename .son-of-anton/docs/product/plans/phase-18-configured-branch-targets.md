# Phase 18: Configured Branch Targets

**Delivery status:** Draft product plan — awaiting developer approval before decomposition.

## TL;DR

**Goal:** Make Son of Anton honor configured branch roles end-to-end so operators can develop, experiment, and close out from the branch they intentionally choose.

**Ships:**

- `defaultBranch` keeps its narrow meaning: the repo's primary `main`/`master` branch
- New `deliveryBaseBranch` controls the primary worktree branch where phase ticket work initially branches off
- New `closeoutBranch` controls where `/soa closeout phase-XX` lands completed stacked PRs and closeout-owned artifact handling
- Missing `closeoutBranch` falls back to `deliveryBaseBranch`, so the common case stays one branch setting
- Operator-facing docs explain configurable branch-role workflows, including release-preview examples without making any one branch name special

**Defers:**

- Automated promotion from an experiment/preview branch into a release branch
- Release orchestration after a preview or experiment branch is accepted
- Any change to GitHub's repository default branch setting

---

Issue #89 exposes a trust gap in SoA's branch model: `orchestrator.config.json` already declares `defaultBranch`, but the field has been overloaded. Some code paths use it as the repo-primary branch, some use it as the initial delivery base, and closeout effectively treats it as the destination for stacked phase landing. That overloading makes staging, release-preview, and experiment flows harder to reason about than they need to be.

This phase splits those meanings into explicit branch roles. `defaultBranch` remains the repo-primary branch. `deliveryBaseBranch` is the branch on the primary worktree where phase work starts. `closeoutBranch` is where completed stacked PRs land. SoA should not infer active delivery or closeout targets from GitHub when the repo config already states them.

## Phase Goal

This phase should leave the product in a state where:

- A consumer repo can set `deliveryBaseBranch` to any intended primary worktree delivery branch, and SoA starts, stacks, rebases, opens PRs, and writes PR metadata against that branch, even if GitHub's repository default branch is different
- A consumer repo can set a closeout target branch in config and `closeout-stack` lands completed stacked PRs and closeout-owned artifacts on that target rather than assuming the delivery default always equals the closeout destination
- A consumer repo can keep `defaultBranch: "main"`, set `deliveryBaseBranch: "main"`, and set `closeoutBranch: "staging"` to test a completed phase in staging before production merge
- Consuming repos are allowed to adopt the new config shape after their current phase work is closed out; no compatibility shim for old meanings is required
- Documentation clearly tells operators how to run configurable branch workflows and where any manual release promotion step begins

## Committed Scope

### Explicit Branch Role Config

- `defaultBranch` means the repo-primary branch, normally `main` or `master`. It is not the delivery base unless `deliveryBaseBranch` also says so.
- `deliveryBaseBranch` means the branch checked out in the primary worktree where new phase ticket branches initially branch off.
- `closeoutBranch` means the branch where `/soa closeout phase-XX` lands completed stacked PRs and any closeout-owned artifact copying or reconciliation.
- Missing `closeoutBranch` resolves to `deliveryBaseBranch`.
- Missing `deliveryBaseBranch` should be treated as a configuration error or an explicit migration target during this phase, not silently conflated with `defaultBranch`, because compatibility is not required.

### Delivery Base Branch Behavior

- Initial ticket branches start from the resolved `deliveryBaseBranch`.
- PR creation bases, restack/rebase targets, stack metadata, PR body ticket links, state repair, and status output agree on the same resolved delivery base branch.
- GitHub-derived `defaultBranchRef` is not allowed to override configured `deliveryBaseBranch`.
- A configured non-`main` delivery base such as `staging`, `preview`, `experiment`, or `release-next` is treated as normal, not exceptional.

### Configured Closeout Target

- Add `closeoutBranch` so closeout can be directed independently of GitHub's repository default and, when needed, independently of the delivery base branch.
- If `closeoutBranch` is absent, closeout uses the resolved `deliveryBaseBranch`.
- `closeout-stack` verifies, fetches, resets, pushes, comments, summarizes, and places closeout-owned ledger/triage/review artifacts against the resolved closeout target where those artifacts are copied or reconciled during closeout.
- Operator-facing errors name the actual branch expected for closeout, not a hardcoded `main` or `defaultBranch`.

### Configurable Branch Workflow

Document supported workflow shapes:

- `main` can be the primary worktree and closeout target, which remains the default.
- A repo can use `defaultBranch: "main"`, `deliveryBaseBranch: "main"`, and `closeoutBranch: "staging"` when phase work starts from production but should land in staging for validation before manual production merge.
- A repo can use `defaultBranch: "main"`, `deliveryBaseBranch: "release-next"`, and omit `closeoutBranch` when phase work should start from and collapse back into a release-preview branch.
- A repo can set `closeoutBranch` separately when stack delivery starts from one branch but closeout-owned copying or reconciliation should land elsewhere.
- Any later promotion between branches is a deliberate manual operation outside SoA closeout.

### Regression Coverage And Docs

- Tests cover a GitHub default branch of `main` with configured `deliveryBaseBranch` set to another branch, proving config wins.
- Tests cover PR base selection, delivery-base rebase behavior, closeout target selection, closeout fallback to `deliveryBaseBranch`, and PR metadata links where applicable.
- README and `docs/template/overview/start-here.md` explain the configured branch model and the manual promotion boundary.
- `docs/template/delivery/delivery-orchestrator.md` reflects the same branch terminology so agents do not keep saying "main" when a repo is configured otherwise.

## Explicit Deferrals

- **Automated promotion command:** No `promote`, `release`, or branch-to-branch promotion command ships in this phase. If a promotion workflow proves stable, promotion can be designed as a separate phase.
- **Release safety policy:** No release checklist, version tag, changelog, deployment, or branch-protection workflow is added here.
- **Changing the GitHub repo default:** SoA should work even when GitHub says `main`; this phase does not change repository settings.
- **Per-phase branch overrides:** Branch selection remains repo config, not plan-level or ticket-level metadata.
- **Multi-branch train matrix:** This phase supports one active configured primary branch and one configured closeout target, not multiple simultaneous trains.
- **Backward compatibility for current overloaded semantics:** No compatibility layer is required. Consuming repos can update after in-flight phase work is closed out.

## Exit Condition

Phase 18 is done when a maintained test or smoke fixture can model a repo whose GitHub default branch and `orchestrator.config.json.defaultBranch` are `main`, while `orchestrator.config.json.deliveryBaseBranch` is another branch, and the delivery stack consistently uses `deliveryBaseBranch` for first-ticket base, restack target, PR base, PR metadata links, and status/handoff language.

The phase is also done when `closeout-stack` can be configured to close onto a chosen `closeoutBranch` and all closeout command output, branch guards, reset/push targets, PR close comments, and closeout-owned artifact handling name that branch. When `closeoutBranch` is absent, the same surfaces resolve to `deliveryBaseBranch`.

## Retrospective

`required` — This phase changes a durable operator workflow boundary: SoA separates repo-primary, delivery-base, and closeout-target branch roles instead of overloading `defaultBranch`. The retrospective should capture whether the naming and defaults were clear enough for real configurable branch-role use.
