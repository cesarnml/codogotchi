# Start Here

This is the entry point for Son of Anton delivery work. Read this before touching any code.

## Immediate next action

Check your repo's roadmap for the current active phase and its status. The handoff file for the active ticket is at `.agents/delivery/<plan-key>/handoffs/<ticket-id>.md` — that is the required input for resuming in-progress work.

## Four developer control points

Son of Anton enforces four gates per phase. Nothing moves forward without explicit developer approval at each:

1. **Product plan approval** — `/soa plan` + `soa-grill-me` produces `docs/product/plans/phase-N-[slug].md` (the why and what). No decomposition starts until the developer approves this artifact.
2. **Ticket approval** — `/soa decompose` + `soa-grill-me` produces `implementation-plan.md` + ticket files (the how). No branches are created until the developer approves the ticket stack.
3. **Ticket-by-ticket review** — in `gated` mode, the orchestrator stops after each `advance` and prints a canonical resume prompt. Developer reviews the PR and explicitly resumes.
4. **Phase closeout** — stacked PRs are never auto-merged. `bun run closeout-stack --plan <path>` requires explicit developer invocation.

## Starting a new phase

```
Stage 1 — Why and What (/soa plan):
1. /soa plan [description or path]  →  soa-grill-me on product scope
2. Developer approves product plan
3. Commit docs/product/plans/phase-N-[slug].md to the configured repo-primary branch

Stage 2 — How (/soa decompose):
4. /soa decompose [plan path]  →  soa-grill-me on ticket decomposition
5. Developer approves ticket stack
6. Commit implementation-plan.md + all ticket-NN-*.md files to the configured repo-primary branch

Execute:
7. bun run deliver --plan <plan-path> start
8. For code tickets, write and commit the failing behavior test with `[red]`
9. bun run deliver --plan <plan-path> post-red
10. Implement, verify, and continue with the next command from `status`
11. For code tickets with subagent review enabled: `post-verify` → `write-subagent-adversarial-review` → `subagent-review` → `reconcile-subagent-review` → `open-pr` (see `delivery-orchestrator.md`)
```

Both the product plan and implementation docs must be committed to the configured
repo-primary branch **before** the orchestrator creates any delivery branches.

The pre-PR subagent gate is a **three-step** flow: the primary agent authors the filled adversarial prompt (`write-subagent-adversarial-review`); the runner step (`subagent-review --subagent …`) consumes that exact prompt and returns findings prose only; `reconcile-subagent-review` compares the ledger to git state and blocks `open-pr` on silent lies. Artifacts are `*-subagent-review.{prompt.md, report.md, ledger.json}`. Outcomes are `clean | patched | deferred | skipped`. Policy surface names stay `subagentReview`, `--subagent-review-policy`, and `subagent-review`.

## Resuming in-progress work

```bash
bun run deliver --plan <plan-path> status        # shows active ticket, current status, and one next command
bun run deliver --plan <plan-path> start         # resume from current ticket
```

Always read the handoff doc at `.agents/delivery/<plan-key>/handoffs/<ticket-id>.md` first.
For code tickets, run `post-red` after the `[red]` commit and before implementation.
Tickets with no testable behavior declare `Red: skip`; doc-only branches skip
the red gate structurally.

## Runtime policy overrides

Override delivery policy for a single run without editing `orchestrator.config.json`:

```bash
bun run deliver --plan <plan-path> \
  --boundary-mode <cook|gated> \
  --subagent-review-policy <required|skip_doc_only|disabled> \
  --pr-review-policy <required|skip_doc_only|disabled> \
  --subagent <claude-cli|codex-cli|cursor-cli> \
  start
```

`--subagent` declares the execution agent's own identity (`claude-cli`, `codex-cli`, or `cursor-cli`). The CLI tries the preferred runner first, then the other programmatic runners, then records an honest `skipped`. No config change needed when switching platforms. For `cursor-cli`, install the Cursor Agent CLI (`agent` on PATH) and authenticate (`agent login` or `CURSOR_API_KEY`).

The resolved policy is persisted in `state.json` as `runPolicy` and governs execution for every invocation that loads it. If `orchestrator.config.json` changes between runs, the orchestrator detects divergence and refuses to continue silently — pass `--baseline orchestrator` to adopt the current config or `--baseline run-policy` to re-apply the persisted runPolicy (it governs execution for the current invocation, not just state):

```bash
bun run deliver --plan <plan-path> --baseline orchestrator <command>
bun run deliver --plan <plan-path> --baseline run-policy   <command>
```

`status` shows the active persisted `run_policy [persisted]` line alongside the config-baseline lines.

## Standalone (non-ticketed) PRs

Small bounded changes that don't warrant a full phase (bug fixes, doc updates, cleanup):

```bash
bun run deliver triage-standalone [--pr <number>]
```

Self-audit is required. A same-type review subagent is optional but recommended for non-trivial changes.

For late external AI review triage after a PR already exists, use the matching
`/soa` wrapper:

```bash
/soa triage-ticket PR#19      # done ticket-linked phase PRs
/soa triage-standalone PR#19  # standalone non-ticket PRs
```

After a phase closeout lands on the configured `closeoutBranch`, run the
supported post-phase advisory triage lane before starting the next phase:

```bash
/soa triage-advisory-observations phase-16
```

This scans completed subagent-review reports for non-blocking **Advisory
Observations** and records explicit operator dispositions in the phase artifact.
It does not patch source files, and it is not a per-ticket pre-PR gate.

For small verified fixes that reveal a review gap worth capturing, use the
quality-control lane after `/soa tao` (or independently when no advisory
observations exist):

```bash
/soa quality-control phase-16: <description>
# or the short alias:
/soa qc phase-16: <description>
```

`/soa qc` applies a bounded fix commit and appends one JSONL record to
`docs/product/review-gaps/ledger.jsonl`. It classifies the gap as
`review-reachable`, `spec-gap`, `qa-gap`, or `completeness-gap` and queues
promotion candidates in `docs/product/review-gaps/promotion-queue.md` without
editing the adversarial-review prompt. Larger or ambiguous work is routed
toward standalone PR triage or `/soa plan`.

The expected post-phase sequence is: **closeout → `/soa tao` → `/soa qc` (when
applicable) → next phase planning**.

## Configured branch roles

`orchestrator.config.json` separates three branch roles:

- `defaultBranch` is the repo-primary branch for source links and committed
  planning docs.
- `deliveryBaseBranch` is the branch where the first ticket branch starts.
- `closeoutBranch` is the branch where `closeout-stack` lands completed stacked
  PRs.

The all-`main` workflow sets all three fields to `main`. A staging workflow can
use `defaultBranch: "main"`, `deliveryBaseBranch: "main"`, and
`closeoutBranch: "staging"` so completed phase work lands in staging first. A
release-preview workflow can set both `deliveryBaseBranch` and `closeoutBranch`
to `release-next`.

Promotion between branches is manual and outside SoA closeout. For example, SoA
can close a phase onto `staging`, but it does not promote `staging` to `main`.

## Key files

| File                                                      | Purpose                                                                             |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `orchestrator.config.json`                                | Runtime config (branch roles, boundary mode, review policy, package manager)        |
| `scripts/soa-sync.sh`                                     | Consumer sync script — links skills, injects agent rules, runs migrations           |
| `scripts/soa-update.sh`                                   | Consumer update script — fetch, subtree merge, sync, and verify upstream content    |
| `docs/template/delivery/delivery-orchestrator.md`         | Full command reference, including stable workflow-contract and optional-DI guidance |
| `docs/template/delivery/son-of-anton.md`                  | Doctrine: why this workflow exists                                                  |
| `docs/template/delivery/tdd-workflow.md`                  | Red-green-refactor contract for ticket implementation                               |
| `docs/template/delivery/issue-tracking.md`                | Issue sizing and Fibonacci point conventions                                        |
| `docs/template/delivery/phase-implementation-guidance.md` | Implementation plan format contract                                                 |
| `.agents/skills/son-of-anton-ethos/SKILL.md`              | `soa-son-of-anton-ethos` behavioral contract for orchestrated delivery              |

> **Canonical templates:** Planning and decomposition outputs must use the templates at `docs/template/stubs/` as their format reference — never model a new ticket or implementation plan on existing docs under `docs/product/delivery/`. Older phases predate the current template and will produce format drift if copied. Use [`docs/template/stubs/ticket.template.md`](../templates/ticket.template.md) for tickets and [`docs/template/stubs/implementation-plan.template.md`](../templates/implementation-plan.template.md) for implementation plans.
