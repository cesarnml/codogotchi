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
3. Commit docs/product/plans/phase-N-[slug].md to main

Stage 2 — How (/soa decompose):
4. /soa decompose [plan path]  →  soa-grill-me on ticket decomposition
5. Developer approves ticket stack
6. Commit implementation-plan.md + all ticket-NN-*.md files to main

Execute:
7. bun run deliver --plan <plan-path> start
8. For code tickets, write and commit the failing behavior test with `[red]`
9. bun run deliver --plan <plan-path> post-red
10. Implement, verify, and continue with the next command from `status`
11. For code tickets with subagent review enabled: `post-verify` → `write-subagent-adversarial-review` → `subagent-review` → `reconcile-subagent-review` → `open-pr` (see `delivery-orchestrator.md`)
```

Both the product plan and implementation docs must be committed to `main` **before** the orchestrator creates any branches.

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

After a phase closeout lands on `main`, run the supported post-phase advisory
triage lane before starting the next phase:

```bash
/soa triage-advisory-observations phase-16
```

This scans completed subagent-review reports for non-blocking **Advisory
Observations** and records explicit operator dispositions in the phase artifact.
It does not patch source files, and it is not a per-ticket pre-PR gate.

## Key files

| File                                                      | Purpose                                                                             |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `orchestrator.config.json`                                | Runtime config (boundary mode, review policy, package manager)                      |
| `scripts/soa-sync.sh`                                     | Consumer sync script — links skills, injects agent rules, runs migrations           |
| `scripts/soa-update.sh`                                   | Consumer update script — fetch, subtree merge, sync, and verify upstream content    |
| `docs/template/delivery/delivery-orchestrator.md`         | Full command reference, including stable workflow-contract and optional-DI guidance |
| `docs/template/delivery/son-of-anton.md`                  | Doctrine: why this workflow exists                                                  |
| `docs/template/delivery/tdd-workflow.md`                  | Red-green-refactor contract for ticket implementation                               |
| `docs/template/delivery/issue-tracking.md`                | Issue sizing and Fibonacci point conventions                                        |
| `docs/template/delivery/phase-implementation-guidance.md` | Implementation plan format contract                                                 |
| `.agents/skills/son-of-anton-ethos/SKILL.md`              | `soa-son-of-anton-ethos` behavioral contract for orchestrated delivery              |

> **Canonical templates:** Planning and decomposition outputs must use the templates at `docs/template/stubs/` as their format reference — never model a new ticket or implementation plan on existing docs under `docs/product/delivery/`. Older phases predate the current template and will produce format drift if copied. Use [`docs/template/stubs/ticket.template.md`](../templates/ticket.template.md) for tickets and [`docs/template/stubs/implementation-plan.template.md`](../templates/implementation-plan.template.md) for implementation plans.
