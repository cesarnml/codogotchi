# Delivery Orchestrator

This repo now includes a small repo-local delivery orchestrator for stacked ticket work.

**Read this document in full before executing any orchestrator command.** The step order below is mandatory and must not be inferred from first principles.

## Critical Step Order

For every code ticket, these steps must run in this exact sequence:

1. `start` — create worktree, materialize handoff
2. Write the failing behavior test and commit it with a `[red]` suffix
3. `post-red` — verify and record the `[red]` commit before implementation
4. Implement + verify (`bun run verify:quiet` inner loop, then `bun run ci:quiet` before open-pr)
5. `post-verify [clean|patched]` — self-audit
6. `write-subagent-adversarial-review` — primary agent authors the filled adversarial prompt (required for code tickets when `subagentReview` is not `"disabled"`)
7. `subagent-review` — advisory subagent pass against that exact prompt (programmatic runner with `--subagent`, or recorder mode)
8. `reconcile-subagent-review` — compare ledger rows to git state since `reviewedHeadSha`; hard-block silent lies before publish (also runs inside `open-pr`)
9. `open-pr` — publish the PR (never before subagent review and reconciliation gates complete)
10. `poll-review` — external AI review window
11. `record-review` — only needed when poll-review leaves ticket in `needs_patch`
12. `advance` — move to next ticket

Tickets declare `Red: required` or `Red: skip` in their metadata block. Code
tickets use `Red: required`; tickets with no testable behavior may declare
`Red: skip`, and doc-only branches also skip `post-red` structurally.

**post-red must precede implementation. write-subagent-adversarial-review must precede subagent-review. subagent-review must precede reconcile-subagent-review. reconcile-subagent-review must precede open-pr. open-pr must precede poll-review.** Skipping or reordering these steps is not supported.

## Phase 14 changes (subagent-review fidelity)

Phase 14 makes the subagent-review ledger semantically honest. Operator-facing docs and skills should describe the same contract:

- **Artifact triplet:** `reviews/<ticket>-subagent-review.{prompt.md, report.md, ledger.json}` — prompt, report, ledger. No dual-name fallback for pre-Phase-14 filenames.
- **Runner selection:** `--subagent <claude-cli|codex-cli|cursor-cli>` at invocation time; optional project default `subagentRunner` in `orchestrator.config.json`. Precedence: flag > config field > hard error (SoA ships no silent default).
- **Outcome vocabulary:** ledger rows use `clean | patched | deferred | skipped` reflecting what the primary agent actually did after the advisory pass.
- **Reconciliation:** `reconcile-subagent-review` runs after `subagent-review` and before `open-pr`. It detects silent lies (unlabeled post-review edits, actionable findings with no patch or deferral) and exits non-zero with named resolution paths. `open-pr` invokes the same gate and accepts `--ack-reconciliation <patched|deferred|clean>` as an operator escape valve.
- **Deferral:** `subagent-review record-deferred --reason "<rationale>"` appends a `deferred` row when findings are consciously not patched.
- **Advisory observations:** non-blocking off-scope-but-real notes belong under the `Advisory Observations` report section, not the blocking `Actionable findings` section. The old `Findings for human review` wording is legacy terminology for this same non-blocking lane.
- **Adversarial prompt prologue:** broadening clauses (extra surfaces, advisory-observation bucket) appear before the narrowing "not a general code review" anchor in `adversarial-review-template.md`.

### Programmatic subagent runners

`subagent-review` can invoke a headless runner when `--subagent` (or `subagentRunner` in config) names one of:

| `runnerKind` | Binary   | Verified invocation (prompt = filled `*-subagent-review.prompt.md` bytes)    |
| ------------ | -------- | ---------------------------------------------------------------------------- |
| `claude-cli` | `claude` | `claude -p <prompt>`                                                         |
| `codex-cli`  | `codex`  | `codex exec [--output-last-message <path>] --color never <prompt>`           |
| `cursor-cli` | `agent`  | `agent --print --trust --output-format text --workspace <worktree> <prompt>` |

Prerequisites: install the binary on PATH. For `cursor-cli`, run `agent login` or set `CURSOR_API_KEY` before delivery. The orchestrator runs the command in the ticket worktree, persists stdout to `*-subagent-review.report.md`, stderr to `*-subagent-review.trace.log`, and records honest `skipped` rows when a runner is unavailable, rate-limited, or violates the advisory-only contract (any file write in the worktree).

Fallback order: try the operator-selected runner first, then each other programmatic runner in stable order (`claude-cli` → `codex-cli` → `cursor-cli`, with the requested runner moved to the front). Ledger rows record `runnerKind` (what ran) and `fallbackFrom` (what was requested when fallback fired).

## Stance

The orchestrator is repo tooling, not app runtime code.

That means:

- the engine lives under `tools/`
- the command wrapper lives under `scripts/`
- tests for the engine live with the tooling code, not with app tests

This keeps the product boundary honest. The delivery tool is a maintainer workflow helper, not app runtime code.

## Module Structure

After EE11, `tools/delivery/` is decomposed into focused single-concern modules.
`orchestrator.ts` is a pure re-export barrel with no logic — it exists only so
external callers can import from one stable path.

| Module                 | Concern                                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| `types.ts`             | All shared TypeScript types and interfaces                                                             |
| `env.ts`               | `.env` parsing (`parseDotEnv`) and environment readiness helpers                                       |
| `runtime-config.ts`    | `OrchestratorConfig` loading, resolution, package-manager inference, and invocation formatting         |
| `context.ts`           | Plain `DeliveryOrchestratorContext` construction from resolved config and platform adapters            |
| `format.ts`            | Human-readable status formatting (`formatStatus`, `formatCurrentTicketStatus`, etc.) with config input |
| `platform.ts`          | Raw platform primitives: `spawnSync`, git worktree parsing, shell helpers                              |
| `platform-adapters.ts` | `createPlatformAdapters(config)` factory that binds runtime/config to platform primitives              |
| `planning.ts`          | Branch and worktree naming (`deriveBranchName`, `deriveWorktreePath`, `findExistingBranch`)            |
| `state.ts`             | State persistence (`loadState`, `saveState`, `normalizeDeliveryStateFromPersisted`)                    |
| `ticket-flow.ts`       | Ticket lifecycle transitions, handoff artifact writing, `materializeTicketContext`                     |
| `notifications.ts`     | Telegram notification events and formatting                                                            |
| `pr-metadata.ts`       | PR title/body construction and AI-review section builders                                              |
| `review.ts`            | Review polling lifecycle, fetcher/triager adapters, artifact parsing                                   |
| `cli-runner.ts`        | `runDeliveryOrchestrator` dispatch switch and explicit command-helper wiring                           |
| `cli.ts`               | Argument parsing (`parseCliArgs`, `getUsage`)                                                          |
| `subagent-runner.ts`   | Runner types and functions (`tryRunner`, `buildRunnerArtifact`, `validateRunnerArtifact`)              |
| `orchestrator.ts`      | Pure re-export barrel — no logic                                                                       |

Each source module has a corresponding test file under `tools/delivery/test/`.
Import from source modules in tests, not from the barrel.

## Runtime Context Boundary

Runtime config is not stored in a module-level singleton. The CLI loads
`orchestrator.config.json`, resolves defaults once, builds a
`DeliveryOrchestratorContext`, and passes that context or its `config` field into
helpers that need runtime values.

The context is intentionally small:

- `config`: resolved branch, plan-root, runtime, package-manager, boundary-mode,
  and review-policy values
- `platform`: platform adapters created by `createPlatformAdapters(config)`
- `invocation`: the package-manager-specific deliver command string used in
  user-facing errors

This keeps dependency direction visible at call sites. Helpers that need branch
or runtime behavior accept `ResolvedOrchestratorConfig`; helpers that need git,
GitHub, filesystem, or process adapters accept `DeliveryOrchestratorContext`.
Tests use local config/context fixtures instead of mutating global module state.

`runtime-config.ts` still owns config loading and validation, but it does not
export `_config`, `initOrchestratorConfig`, or `getOrchestratorConfig`.
`platform-adapters.ts` no longer reads runtime config directly; all adapter
methods close over the config passed to `createPlatformAdapters(config)`.
Formatters receive config explicitly so status rendering and boundary guidance
do not depend on hidden process state.

## Configurable Core

The orchestrator core now reads `orchestrator.config.json` at the repo root so
branch, plan-root, runtime-internal, bootstrap defaults, ticket-boundary
behavior, and review policy are not hardcoded:

```json
{
  "defaultBranch": "main",
  "planRoot": "docs",
  "runtime": "bun",
  "packageManager": "bun",
  "ticketBoundaryMode": "cook",
  "reviewPolicy": {
    "subagentReview": "skip_doc_only",
    "prReview": "skip_doc_only"
  },
  "prReviewAgents": [
    { "login": "coderabbitai", "name": "coderabbit" },
    { "login": "qodo-merge", "name": "qodo" }
  ],
  "subagentRunner": "codex-cli",
  "primaryAgent": "claude"
}
```

Subagent selection precedence is **`--subagent` flag > `subagentRunner` config field > hard error**. Valid `subagentRunner` / `--subagent` values: `claude-cli`, `codex-cli`, `cursor-cli`. SoA ships no built-in silent default: a fresh repo with neither flag nor config field set is required to make the choice explicit before any subagent review runs. `primaryAgent` is free-form (e.g. `claude`, `codex`, `cursor`, `composer`, `copilot`, `aider`) and is recorded on every ledger row as `primaryAgent`; absent flag/config defaults to `"unknown"`. Cross-family review (e.g. claude primary + codex-cli or cursor-cli subagent) is the documented best practice but not enforced — the operator chooses, the ledger records both fields so cross-family achievement is computable post-hoc.

All fields are optional. When the file is absent, the orchestrator infers sensible defaults:

- `defaultBranch`: `"main"`
- `planRoot`: `"docs"` (plans live at `{planRoot}/product/delivery/<phase>/implementation-plan.md`)
- `runtime`: `"bun"` (`"bun"` uses `Bun.spawnSync`, `"node"` uses `child_process.spawnSync` inside the orchestrator implementation)
- `packageManager`: inferred from lockfile (`bun.lock` → `"bun"`, `pnpm-lock.yaml` → `"pnpm"`, `yarn.lock` → `"yarn"`, `package-lock.json` → `"npm"`, fallback `"npm"`) for worktree bootstrap behavior
- `ticketBoundaryMode`: `"cook"`
- `reviewPolicy.subagentReview`: `"skip_doc_only"`
- `reviewPolicy.prReview`: `"skip_doc_only"`

Valid `reviewPolicy` stage values are:

- `"required"` — the stage must complete before the workflow can proceed.
- `"skip_doc_only"` — the stage is required for code PRs but automatically skipped for doc-only PRs (PRs whose changed files are all `.md`).
- `"disabled"` — the stage is never run, regardless of PR content.

Invalid values and unknown keys are rejected at config load with a clear error.

`reviewPolicy.subagentReview` governs the pre-PR internal agent review step (`subagent-review` command). `reviewPolicy.prReview` governs the external AI PR review polling window. `prReviewAgents` is a list of `{ login, name }` entries used by the fetcher script to identify external review bots by GitHub login. Runner selection for `subagent-review` is done at invocation time via `--subagent <claude-cli|codex-cli|cursor-cli>` — not in config.

Supported `ticketBoundaryMode` values are:

- `cook`
- `gated`

The internal convention below `planRoot` is fixed: `{planRoot}/product/delivery/<phase>/implementation-plan.md`. Only the top-level directory name is configurable.

The supported operator entrypoint is `bun run deliver --plan ...`. The orchestrator core is intentionally generic but does not attempt to be a fully validated multi-runtime CLI package.

## Plan-Driven, Not Phase-Hardcoded

The engine is generic. It does not fundamentally belong to Phase 02.

What is phase-specific is:

- which implementation plan to read
- where local state and review artifacts are stored
- which ticket IDs, titles, and files exist in that plan

So the orchestrator takes a plan path:

- `--plan docs/product/delivery/phase-NN/implementation-plan.md`

That is the canonical interface. The tool is primarily AI-facing, so the explicit plan artifact is more important than a phase nickname.

## What It Owns

The orchestrator owns process mechanics:

- reading ticket order from the plan
- durable local state under `.agents/delivery/<plan-key>/`
- per-ticket handoff artifacts under `.agents/delivery/<plan-key>/handoffs/`
- deterministic branch and worktree naming
- copying a fixed repo-root ignored-file bootstrap allowlist into fresh ticket worktrees when those files exist in the invoking worktree and are missing in the target worktree (`.env`, `.env.local`, `.env.development`, `.env.test`, `.gitignore`)
- bootstrapping fresh ticket worktrees using lockfile-aware package-manager defaults before implementation starts
- materializing bounded delivery artifacts into started ticket worktrees so local continuation does not depend on manual artifact copying or rediscovery
- stacked PR base chaining
- idempotent PR open/update behavior for already-pushed ticket branches
- a 6/12-minute AI-review polling loop after PR open (two checkpoints: 6 minutes and 12 minutes)
- invoking the repo-local `pr-review` fetcher and persisting split review artifacts when AI review is detected
- optional Telegram milestone notifications for long-running delivery runs
- blocking advancement until review is explicitly recorded or auto-recorded as `clean` after the final polling check
- refreshing the current PR body from recorded follow-up notes immediately before advancing to the next ticket
- resolving native GitHub inline review threads for patched AI-review findings when the saved artifact exposes a resolvable thread identity
- sharing ticket-linked and standalone post-PR review handling through common lifecycle helpers for detected-review processing, clean/timeout recording, metadata refresh, and final persistence

The orchestrator does **not** own AI-review detection heuristics or triage judgment.

That boundary is intentional. The repo-local `soa-pr-review` skill under `.agents/skills/pr-review/` already defines the repo stance for AI review:

- comments are advisory, not gospel
- weak or mis-scoped comments should be pushed back on
- only prudent, concrete fixes should be patched

So the orchestrator only consumes the skill hook contracts:

- fetcher:
  - `detected=false`: keep polling, or auto-record `clean` on the final check
  - `detected=true`: save `reviews/<ticket>.fetch.json`, then call the triager hook and persist `reviews/<ticket>.triage.json`
  - preserves supported-vendor identity, reviewed head SHA, native thread identity when available, and inline-comment resolution/outdated metadata in the saved fetch artifact
- triager:
  - returns `clean`, `needs_patch`, or `patched`
  - returns the final note plus concise action and non-action summaries
  - may be overridden with `AI_CODE_REVIEW_TRIAGER` without changing orchestrator code

In consumer repos, the default hook lookup prefers
`.son-of-anton/.agents/skills/pr-review/scripts/...` when the subtree is
present, then falls back to `.agents/skills/pr-review/scripts/...` for the
source repo. This avoids collisions when a consumer repo already has its own
`.agents/skills/pr-review` directory.

In this repo, supported external AI-review vendors are currently:

- `coderabbit`
- `qodo`
- `greptile`
- `sonarqube`

Other vendors are out of scope unless the repo-local `soa-pr-review` skill is deliberately expanded.

For `sonarqube`, the repo-local fetcher reads GitHub check-run annotations rather than native PR review threads and intentionally keeps only failed-check annotations in the normalized fetch artifact. Lower-severity warning annotations remain available in SonarQube itself but do not enter the orchestrator triage loop by default.

The absence of `pr-review` comments after the final 12-minute polling check is not itself a blocker. In that case, the orchestrator records the review as `clean`, updates the PR metadata, and continues unless another real ambiguity or prerequisite issue exists.

Doc-only PRs (where the diff touches only `.md` files) skip the review window only when `reviewPolicy.prReview` is `"skip_doc_only"` (or the stage is fully `"disabled"` for all PRs). External AI agents review code; the developer reads docs. When `open-pr` detects a doc-only diff, it sets a `doc_only` flag in state, and `poll-review` uses the configured policy to decide whether to auto-record `skipped` immediately or wait through the normal review window.

When the triager hook resolves to `clean` or `patched`, `poll-review` records that result immediately. When it resolves to `needs_patch`, the ticket moves into an intermediate `needs_patch` state with the saved fetch/triage artifacts and triage note. From there the follow-up must conclude as either `patched` or `operator_input_needed`. PR body updates remain best-effort in either case.

Review artifact persistence now follows a hard split:

- `reviews/<ticket>.fetch.json` is the only persisted source of normalized vendor review evidence
- `reviews/<ticket>.triage.json` is the only persisted source of repo-local review judgment and triage side effects
- `state.json` stores only compact index/control-plane review fields such as artifact paths, `reviewOutcome`, `reviewRecordedAt`, and optionally `reviewHeadSha`
- no rendered `.txt` review artifact is persisted
- a stable `fetch.json` without `triage.json` is an incomplete internal state and should be surfaced as such rather than treated as a completed review

At this point in the repo, `poll-review`, `record-review`, `triage-ticket`, and `triage-standalone` are intentionally thin mode-specific shells around the same post-PR lifecycle helpers. Ticket-linked flow still owns stacked state transitions and standalone flow still owns PR discovery plus author-body preservation, but the semantic review handling between those edges is shared.

### Ticket PR triage (`done` tickets)

`poll-review` only targets tickets in **`in_review`**. After a ticket is **`done`**, use **`triage-ticket <ticket-id>`** when external AI review comments arrived late and you want to re-fetch, re-run the repo triager, persist updated artifacts under the plan reviews directory, refresh delivery state (while keeping the ticket **`done`**), and refresh the PR body (best-effort). The old `reconcile-late-review` command remains a backwards-compatible alias.

Run it from a worktree where `.agents/delivery/<plan-key>/state.json` for that plan is authoritative (this repo does not discover state across worktrees for you). The ticket must still have a stored **`prNumber`**. The command uses a short single-interval poll so the first check runs immediately; re-run if vendors are still in flight.

### Post-phase advisory-observation triage

After the full stacked phase is closed out onto `main`, run advisory-observation
triage before starting the next phase. The `/soa` wrapper is the user-facing
entrypoint:

```bash
/soa triage-advisory-observations phase-16
```

The underlying orchestrator command is:

```bash
bun run deliver --plan docs/product/delivery/phase-16/implementation-plan.md \
  triage-advisory-observations --dispositions <path>
```

The command scans completed subagent-review report sidecars for the
`Advisory Observations` section, excludes `Actionable findings`, and writes
operator dispositions to
`docs/product/delivery/<phase>/advisory-observation-triage.json`. Dispositions
are explicit input; the command does not infer or apply them, and it never
patches source code. This is a post-phase audit lane, not an additional
per-ticket pre-PR gate.

Closeout/status summaries may warn when advisory observations are untriaged or
when clean/completed subagent-review evidence is suspiciously missing or empty.
Those warnings preserve the boundary: `Actionable findings` still govern
pre-PR reconciliation blockers, while `Advisory Observations` require later
operator disposition.

## Ticket Context Reset

The orchestrator also owns the repo-side context reset contract for stacked ticket work.

When a ticket starts, the orchestrator writes a handoff artifact under:

- `.agents/delivery/<plan-key>/handoffs/`

That handoff is the narrow context that the next ticket worker should begin from alongside the current repo state and required docs.

`start` must also leave the started ticket worktree locally self-sufficient for active-ticket continuation. In practice that means the target worktree receives:

- `.agents/delivery/<plan-key>/state.json`
- the current ticket handoff artifact
- handoff and review artifacts for the current ticket and immediate predecessor only

This is intentionally bounded context, not whole-phase mirroring.

For the **first ticket in a new phase**, there may be no prior-ticket handoff or review artifacts beyond the implementation plan, the ticket doc, and current repo state. That is expected, not a blocker.

The handoff includes:

- the phase plan path
- the current ticket id, title, branch, base branch, and worktree path
- the required docs to re-read before implementation
- prior ticket PR and review metadata when there is a previous ticket
- explicit stop conditions for when the worker should pause instead of widening scope

This does not automatically create a brand-new agent session, but it is the current repo mechanism for reducing reasoning carryover between tickets while preserving stacked branch continuity.

For ticket `01`, `start` is the command that initializes the first ticket context for the phase. After `start`, read the locally materialized handoff artifact from the started ticket worktree; before that, do not treat the absence of a prior-ticket handoff as missing workflow state.

**No read-ahead during the review window.** The agent does nothing while waiting on external AI review. The wait is free (LLM idle during subprocess sleep). Read-ahead during the window burns context that is dead weight at the next ticket boundary. Be sabaai sabaai.

## Runtime Policy Overrides

Pass explicit flags to override delivery policy for a single run without editing `orchestrator.config.json`. The resolved policy persists in `state.json` as `runPolicy` and governs the entire run.

**Available flags:**

| Flag                       | Values                              | Effect                                                                                                     |
| -------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `--boundary-mode`          | `cook\|gated`                       | Override ticket-boundary mode                                                                              |
| `--subagent-review-policy` | `required\|skip_doc_only\|disabled` | Override subagent review gate                                                                              |
| `--pr-review-policy`       | `required\|skip_doc_only\|disabled` | Override PR review gate                                                                                    |
| `--subagent`               | `claude-cli\|codex-cli\|cursor-cli` | Declare execution agent identity; tries preferred first, then other programmatic runners, then honest skip |
| `--baseline`               | `orchestrator\|run-policy`          | Resolve divergence on resume (see below)                                                                   |

**Divergence recovery:** If `orchestrator.config.json` changes between runs, resume detects drift on the four bounded policy fields and refuses to continue until the operator resolves it:

```bash
# Adopt current repo config as the new active policy:
bun run deliver --plan <plan> --baseline orchestrator <command>

# Re-apply the persisted runPolicy — it governs execution for this invocation (not just state):
bun run deliver --plan <plan> --baseline run-policy <command>
```

Both baselines accept additional override flags to fine-tune the resolved policy before persisting it.

**Status output:** The active persisted `runPolicy` appears as `run_policy=... [persisted]` in `status` output, below the config-baseline `boundary_mode` and `review_policy` lines. Divergence between those lines is resolved with `--baseline`.

## Ticket Boundary Modes

EE7 makes the ticket-boundary policy explicit.

- `cook`: repo default. `advance` marks the current ticket `done` and
  immediately starts the next pending ticket by reusing the shared `start`
  mechanics. The next worktree, branch, and handoff are created automatically.
- `gated`: `advance` marks the current ticket `done`, stops, and prints reset
  guidance plus a ready-to-paste resume prompt for the next agent session.
  `advance` does **not** create the next handoff or worktree; `start` remains
  the command that initializes the next ticket.

For `gated`, the canonical resume prompt is:

```text
Immediately execute `bun run deliver --plan <plan> start`, read the generated handoff artifact as the source of truth for context, and implement <next-ticket-id>.
```

Operator reset guidance in `gated`:

- prefer `/clear` for minimum token use
- use `/compact` only when intentionally preserving compressed carry-forward
  context

**Handoff artifact `modified_sections`.** The handoff now includes a `## Modified Sections` block extracted from the ticket's `## Scope` section. Read only the file sections listed there — do not re-read full files. This keeps per-ticket context bounded as implementation files grow across the phase.

That policy applies only to ticket-linked delivery PRs. Standalone manual `triage-standalone` runs for non-ticket PRs do not have a next-ticket boundary, so there is no analogous look-ahead rule there.

## Syncing Existing Work

If a phase was already partially delivered before the orchestrator was introduced, `sync` can infer progress from the repo when the local state file is absent:

- if a ticket branch exists and the next ticket branch also exists, the earlier ticket is inferred as `done`
- if a ticket branch exists and has an open PR but no next branch yet, it is inferred as `in_review`
- if a ticket branch exists without a PR, it is inferred as `in_progress`
- otherwise it remains `pending`

That inference is intentionally conservative. It reconstructs enough state to resume a stacked phase without requiring a fresh restart.

## Post-verify (ticket stacks)

After **build mode** (implementation and automated verification), the agent switches to **post-verify review mode**: a deliberate pass over the diff and ticket acceptance before publishing the branch for external AI code review. Stay in the same implementation session — this is a mode switch, not a handoff. For code tickets, build mode begins only after `post-red` records the failing-test commit.

Use the verification commands with two distinct purposes:

- Use your repo's fast verify command for the inner loop while implementing (e.g. `bun run verify:quiet`).
- Use your repo's full CI command as the pre-`open-pr` gate for code tickets (e.g. `bun run ci:quiet`).
- Keep format and scoped tests in the inner loop as needed.

The `post-verify` command **records** that the post-verify review pass completed (ticket status, outcome, and timestamp in local delivery state). It does **not** run checks or read the diff; the agent performs verification in build mode and the diff review in post-verify mode, then invokes this command.

The command accepts an optional outcome argument. When the outcome is `patched`,
record one or more patch-commit SHAs so the PR body can link the exact
post-verify follow-up commits:

```bash
bun run deliver --plan <plan> post-verify          # defaults to "clean"
bun run deliver --plan <plan> post-verify clean    # no changes during post-verify review
bun run deliver --plan <plan> post-verify patched <sha...>  # post-verify review found and fixed issues
```

When omitted, outcome defaults to `clean`. The `status` command renders the outcome alongside the completion timestamp. A recorded post-verify patch commit must use a subject suffix of `[post-verify]`.

**Before `post-verify`, confirm at least:**

- The diff matches the ticket and handoff; no unrelated scope crept in.
- Automated verification for this change is green, with `bun run ci:quiet` completed for code tickets before publishing.
- Code tickets passed `post-red` before implementation began; tickets with no testable behavior declared `Red: skip` or were structurally doc-only.
- Higher-risk areas changed in the diff (data shape, migrations, auth, API contracts) got a second read in post-verify mode.
- The delivery ticket doc has an updated **Rationale** when behavior or trade-offs changed (repo policy).

Then run `post-verify`, then (if `subagentReview` is enabled) `write-subagent-adversarial-review`, then `subagent-review`, then `reconcile-subagent-review`, then `open-pr`.

## Subagent adversarial review (ticket stacks)

When `reviewPolicy.subagentReview` is `"required"` or `"skip_doc_only"`, code tickets must complete the two-step pre-PR subagent gate before `open-pr`: prompt authoring, then advisory runner review.

**Role split:**

- **Primary agent** executes and patches during build and post-verify mode, authors the filled adversarial prompt, applies any prudent patches from subagent findings, and records the final review outcome.
- **Review subagent** is an advisory runner — a second AI pass before the PR is published. It probes the attack surfaces in the written prompt and returns findings prose only. It must not modify any files in the worktree. The primary agent decides what to patch and commits with a `[subagent-review]` suffix when it applies subagent-driven fixes.
- **External AI vendors** (e.g. CodeRabbit, Qodo) review post-publication during `poll-review`.

**Step 1 — Author the prompt (`write-subagent-adversarial-review`):**

1. Read `docs/template/delivery/adversarial-review-template.md`. Fill in invariants, attack surfaces (including the seven diff-derived classes), and diff context from the current ticket diff and spec. This is primary-agent work — the subagent does not author its own brief.
2. Record the filled prompt:

```bash
bun run deliver --plan <plan> write-subagent-adversarial-review
# optional: --prompt-file <path> when the filled template already exists on disk
```

The command persists the prompt under `reviews/<ticket>-subagent-review.prompt.md`, commits it from the ticket worktree, and stores `subagentAdversarialPromptPath` on the ticket in delivery state.

**Step 2 — Run advisory review (`subagent-review`):**

**Runner selection:** The execution agent declares its own identity via `--subagent <claude-cli|codex-cli|cursor-cli>`. The CLI tries the preferred runner first, falls back to the other programmatic runners in order, and records an honest `skipped` artifact if none are available. No config change is needed when switching agent platforms (Claude Code, Codex, Cursor Agent CLI, etc.). The verified headless form for `cursor-cli` is `agent --print --trust --output-format text --workspace <worktree> <prompt>`.

The runner receives the exact bytes from `reviews/<ticket>-subagent-review.prompt.md`, invokes verified headless forms (`claude -p` / `codex exec` / `agent --print --trust --output-format text --workspace <worktree>`), persists runner prose to `reviews/<ticket>-subagent-review.report.md`, and writes a `SubagentRunnerArtifact` to `reviews/<ticket>-subagent-review.ledger.json` whose `filledPrompt` and `rawOutput` fields are repo-relative paths to those sidecars (not embedded text). The orchestrator stages, commits, and pushes the JSON plus sidecar files from the ticket worktree. `open-pr` fails closed when `subagentReview` is not `"disabled"` and a non-skipped outcome is recorded but the artifact file is missing.

**Advisory-only contract:** The runner must not write files. If the worktree has new modifications after the runner exits, the CLI records `outcome: skipped` with `terminatedReason: advisory_violation` — not a completed clean review. Non-zero exit codes, empty output, and rate-limit signatures are also recorded as non-`completed` termination; the CLI refuses `outcome: clean` unless `terminatedReason` is `completed`.

3. **Stay idle. No read-ahead.** Wait for the runner subprocess to exit before doing anything else.
4. The primary agent reads findings, applies any prudent patches, then records:

```bash
bun run deliver --plan <plan> subagent-review clean    # no primary-agent patches from subagent findings
bun run deliver --plan <plan> subagent-review patched <sha...>  # primary agent applied subagent-driven fixes
bun run deliver --plan <plan> subagent-review record-deferred --reason "<rationale>"  # conscious deferral
```

Without `--subagent`, the CLI is a state recorder only and does not invoke a runner. With `--subagent`, the CLI invokes the runner against the persisted prompt, enforces the advisory-only contract, writes the runner artifact, and records the detected outcome. Primary-agent patch commits that respond to subagent findings must use a subject suffix of `[subagent-review]`.

**Step 3 — Reconcile ledger vs git (`reconcile-subagent-review`):**

After the primary agent finishes any subagent-driven patches (or records deferral), run reconciliation before publishing:

```bash
bun run deliver --plan <plan> reconcile-subagent-review
```

The command compares commits since the row's `reviewedHeadSha` against the reviewed file set and the report's actionable-findings section. It **hard-blocks** when the ledger would silently lie:

- **Condition A** — reviewed paths changed without a `[subagent-review]`-labeled commit touching them and no `deferred` row exists.
- **Condition B** — the report lists actionable findings but no qualifying patch commit or `deferred` row exists.

Resolution paths are named in the error text: amend the patch subject, `subagent-review record-deferred --reason "..."`, or `open-pr --ack-reconciliation <patched|deferred|clean> [--commit <sha>] [--reason "<text>"]`. `open-pr` runs the same gate internally; use the explicit step for diagnostics.

**Doc-only tickets** auto-skip subagent review only when `reviewPolicy.subagentReview` is `"skip_doc_only"`.

When `reviewPolicy.subagentReview` is `"disabled"`, `open-pr` does not require `subagent_review_complete` status and tickets at `verified` may proceed directly to `open-pr`.

If the subagent is unavailable, set `subagentReview: "disabled"` in `orchestrator.config.json` to bypass the gate.

## Commands

Use the supported repo command:

```bash
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md status
```

### Worktree guard

Most commands require execution from the **active ticket's worktree** — the directory set as `worktreePath` in the ticket state. Running a guarded command from any other directory fails immediately with the exact recovery command:

```
Error: Command '<cmd>' for ticket <id> must be run from its worktree.
Current directory: <cwd>
Expected worktree: <worktreePath>
Recovery: cd <worktreePath> && bun run deliver --plan <plan> <cmd>
```

**Commands exempt from the worktree guard** (safe to run from any directory):

- `status`
- `sync`
- `start`

All other commands are guarded. The guard fires after `loadState` so the expected worktree path is always derived from recorded state, not from the invoking directory.

### Stable workflow contract boundary

Some delivery-tool workflow and state-guard failures carry a stable
machine-readable identity in addition to the human-readable operator message.
This boundary is intentionally narrow:

- targeted workflow/state guards such as `open-pr` missing `post-verify`
- targeted workflow/state guards such as `open-pr` missing `subagent-review`
- ticket-advance guards that block advancement before review is recorded
- the closely related wrong-worktree guard in `assertWorktreeGuard`

These codes are a contributor contract for tests and automation. The human
message is still the operator-facing guidance and may be clarified or rewritten
without changing the contract identity.

Current examples:

- `workflow.open_pr.requires_post_verify`
- `workflow.open_pr.requires_subagent_review`
- `workflow.open_pr.requires_runner_review`
- `workflow.open_pr.invalid_state`
- `workflow.advance.requires_reviewed_ticket`
- `workflow.worktree_guard.wrong_worktree`

This is not a repo-wide error framework. Low-level config, runtime, platform,
and general process failures remain plain errors unless a later phase expands
the boundary deliberately.

### Optional-DI extension rule

When adding a new optional dependency hook to a delivery helper, optional means
the existing behavior must remain unchanged when the hook is omitted. New
behavior runs only when the hook is explicitly supplied.

Treat this as an extension rule, not a suggestion:

- omitted optional hooks must be no-ops by default
- tests should cover both omitted-hook and supplied-hook paths
- adding an optional hook must not force unrelated callers or tests to change

### Testing stance for stable workflow contracts

For contract-bearing workflow/state guards, assert the stable code first and
only then check narrow message content that is intentionally part of the
operator guidance.

Good test stance:

- assert `workflow.open_pr.requires_post_verify`
- assert the message still mentions `post-verify`

Bad test stance:

- assert the full English sentence verbatim when the code already carries the
  machine-stable identity

Outside this narrow workflow-contract boundary, tests may still assert prose
directly when no machine-readable contract exists.

Available commands:

- `sync`
- `status`
- `repair-state`
- `triage-standalone [--pr <number>]`
- `start [ticket-id]`
- `post-red [ticket-id]`
- `post-verify [ticket-id] [clean|patched] [patch-commit-sha ...]`
- `write-subagent-adversarial-review [ticket-id] [--prompt-file <path>]`
- `subagent-review [ticket-id] [clean|patched <sha>] [--force] [--subagent <claude-cli|codex-cli|cursor-cli>]`
- `subagent-review record-deferred --reason "<rationale>" [ticket-id]`
- `reconcile-subagent-review [ticket-id]`
- `open-pr [ticket-id] [--ack-reconciliation <patched|deferred|clean>] [--commit <sha>] [--reason "<text>"]`
- `poll-review [ticket-id]`
- `triage-ticket <ticket-id>`
- `triage-advisory-observations --dispositions <path>`
- `record-review <ticket-id> <clean|patched|operator_input_needed> [note]`
- `advance`
- `restack [ticket-id]`

Separate post-delivery closeout command:

- `bun run closeout-stack --plan <plan-path>`

For a fresh phase start, `start` initializes ticket `01` context. Do not expect prior PR/review handoff state for the first ticket.

### `status` output format

`status` always prints one next command derived from the active ticket's current status:

```
Active ticket: <id> — <title>
Status: <state>
Next command: bun run deliver --plan <path> <next-command>
```

When all tickets are `done`, it prints the phase-complete signal instead:

```
Phase complete. Awaiting developer review.
```

No next command is printed in that case. A cook-mode agent self-terminates; the developer controls closeout.

### `post-verify` — doc-only early failure

When `post-verify` is run on a doc-only ticket (a ticket whose branch diff touches only `.md` or `.json` files) and there are **no commits** on the branch ahead of origin, the command fails immediately with:

```
Error: No commits on branch for doc-only ticket <id>. Add or update documentation files before continuing.
```

This prevents the ticket from silently advancing to `open-pr` with an empty diff. The check runs before any state update.

### `advance` — phase-complete signal

When `advance` marks the **final ticket** `done` and no pending tickets remain, it prints:

```
Phase complete. Awaiting developer review.
```

No next command follows. In cook mode the agent self-terminates at this point; gated mode was already stopped. The developer runs `closeout-stack` to merge.

## Typical Flow

Default `cook` flow (with repo-default `skip_doc_only` review policy):

```bash
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md start
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md post-red
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md post-verify [clean|patched] [patch-commit-sha ...]
# for code tickets when subagentReview is enabled:
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md write-subagent-adversarial-review
# pass --subagent <claude-cli|codex-cli|cursor-cli> to run the advisory subagent programmatically, then record:
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md subagent-review [clean|patched] [patch-commit-sha ...]
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md reconcile-subagent-review
# for doc-only tickets under skip_doc_only, subagent-review auto-records skipped (no prompt step)
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md open-pr
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md poll-review
# poll-review auto-records clean/skipped when prReview is disabled or no findings detected — skip record-review in those cases
# only run record-review when poll-review leaves the ticket in needs_patch state
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md record-review PN.NN patched "patched the two actionable correctness issues"
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md advance
```

With `subagentReview: "required"` in `orchestrator.config.json`, the subagent step is mandatory before `open-pr` for code tickets:

```bash
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md start
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md post-red
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md post-verify [clean|patched] [patch-commit-sha ...]
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md write-subagent-adversarial-review
# execution agent passes --subagent <its-identity>; runner returns findings prose only; primary agent patches if prudent, then record:
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md subagent-review [clean|patched] [patch-commit-sha ...]
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md reconcile-subagent-review
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md open-pr
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md poll-review
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md advance
```

`gated` flow:

```bash
bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md advance
# reset context now; prefer /clear and use /compact only when compressed carry-forward is intentional
# next agent session prompt:
# Immediately execute `bun run deliver --plan docs/product/delivery/phase-NN/implementation-plan.md start`, read the generated handoff artifact as the source of truth for context, and implement PN.NN+1.
```

After the developer has reviewed the full stacked PR chain and is ready to merge it, use:

```bash
bun run closeout-stack --plan docs/product/delivery/phase-NN/implementation-plan.md
```

`closeout-stack` is intentionally separate from `deliver`. It handles stacked PR merge choreography rather than ticket implementation state: for each reviewed slice in ticket order, it runs `git merge --squash` locally (a 3-way merge, robust against parent-branch patches), commits with the PR title, pushes to `main`, closes the PR, and deletes the remote branch. This produces one squash commit per ticket on `main` without rebasing child branches. When squash hits conflicts (often after prior tickets landed as new squash SHAs), it resets to `origin/main` and replays the PR using `gh pr view`’s commit list and sequential `git cherry-pick` instead (merge commits use `-m 1`), which may create more than one commit for that ticket.

For a non-ticket PR, run the manual standalone path:

```bash
bun run deliver triage-standalone
# or: bun run deliver triage-standalone --pr 32
```

For standalone PRs, the internal review contract is behavior-first, not state-recorded:

- implement
- use `verify:quiet` for the fast inner loop
- run `ci:quiet` before publication for non-doc code changes so the final local gate matches the pre-push hook
- run the post-verify diff review and re-check risky areas
- for non-trivial code changes, run a same-type review subagent informally before `triage-standalone`
- run standalone `triage-standalone` as the orchestrator-visible external review gate

In standalone mode, `post-verify` and `subagent-review` are expected preflight discipline, not orchestrator gates. The orchestrator can tell the agent to do them, but without standalone state it cannot verify, audit, or block on them. Only standalone `triage-standalone` is an orchestrator-visible gate today.

The ticket-only commands `post-verify`, `subagent-review`, `open-pr`, `poll-review`, `record-review`, and `advance` do not apply to standalone PRs because there is no ticket state to update. That architectural constraint does not remove the underlying review discipline; it does mean the post-verify review pass and optional subagent pass remain guided discretion in standalone mode rather than durable workflow state.

If standalone delivery ever needs true post-verify or subagent-review gate semantics, add a lightweight standalone state artifact first. Do not present soft preflight discipline as a hard gate without durable evidence.

If a parent ticket was squash-merged onto `main`, run:

```bash
bun run deliver restack
```

from the current child ticket worktree before continuing review. `restack` infers the delivery plan and current ticket from the checked-out branch, fetches `origin`, rebases away the old parent ancestry, and updates the open PR base/body so GitHub review follows the new stack shape. If branch inference is ambiguous, pass `--plan` explicitly.

If local state drifts from repo reality, use `repair-state` to snapshot the stale state file, rebuild clean state from current repo facts, and print the repaired fields before resuming delivery.

## Optional Telegram Notifications

The orchestrator can emit best-effort Telegram notifications for milestone events such as:

- ticket started
- PR opened
- review window ready
- review recorded
- ticket completed
- run blocked

Notifications are optional and advisory. They must never block orchestrator progress if delivery to Telegram fails.

Enable them by setting both env vars in your repo's `.env` file (or your shell environment):

```bash
# .env — Telegram notifications for Son of Anton delivery milestones
TELEGRAM_BOT_TOKEN=your-bot-token-here
TELEGRAM_CHAT_ID=your-chat-id-here
```

The orchestrator reads these via `process.env` at startup. If either is absent or empty, the notifier returns `{ kind: 'noop', enabled: false }` and all notification calls are skipped — no errors, no warnings, no blocked progress.

To get a bot token: create a bot via [@BotFather](https://t.me/BotFather) on Telegram. To get your chat ID: send a message to your bot and call `https://api.telegram.org/bot<TOKEN>/getUpdates` — the `chat.id` field in the response is your `TELEGRAM_CHAT_ID`.

When those env vars are absent, the notifier stays disabled and the orchestrator behaves normally.

## Review Artifact Location

Fetched review output is written under:

- `docs/product/delivery/<plan-key>/reviews/`

Generated handoff artifacts are written under:

- `.agents/delivery/<plan-key>/handoffs/`

State is written under:

- `.agents/delivery/<plan-key>/state.json`

### State file and primary checkout (multi-worktree)

For active ticket continuation, `start` writes the authoritative bounded continuation set into the started ticket worktree. That means the started worktree is the local source of truth for continuing that ticket.

The orchestrator also writes `state.json` in the repo directory where you run `deliver` (the current working directory). If you use **one ticket worktree per ticket** and a **separate `main` clone** for `closeout-stack` or other commands, the `main` checkout’s delivery tree does **not** update automatically.

Fetched review artifacts under `reviews/` and generated handoff artifacts under `handoffs/` are still written under the **same** path relative to the worktree where each command ran. Across a stacked phase, full history is therefore often **spread across multiple ticket worktrees** — the final worktree is **not** guaranteed to contain every `reviews/<ticket>-*.json` or `handoffs/<ticket>-handoff.md` produced earlier.

**Recommendation:**

- After each successful `advance`, refresh the **primary / `main` checkout** so tooling run from `main` stays aligned with reality.
- Copy **`state.json`** from the worktree where that advance just ran (only that file carries the authoritative stack index: PR numbers, branch names, ticket statuses).
- **Merge** **`reviews/`** and **`handoffs/`** from that same worktree into the primary checkout — `reviews/` to `docs/product/delivery/<plan-key>/reviews/` and `handoffs/` to `.agents/delivery/<plan-key>/handoffs/` (per-ticket filenames normally do not collide). Periodically — and **always before `closeout-stack`** if you did not mirror after every ticket — walk **every** ticket worktree for the plan and copy any missing `reviews/*` and `handoffs/*` into primary so **all** local review and handoff evidence lives in the primary checkout, not stranded in an older worktree.

Example (adjust paths and plan key; `final-wt` is the worktree that completed the last ticket):

```bash
mkdir -p /path/to/main-clone/docs/product/delivery/<plan-key>/reviews \
         /path/to/main-clone/.agents/delivery/<plan-key>/handoffs

cp /path/to/final-wt/.agents/delivery/<plan-key>/state.json \
   /path/to/main-clone/.agents/delivery/<plan-key>/state.json

for wt in /path/to/phase-wt-01 /path/to/phase-wt-02 /path/to/phase-wt-NN; do
  cp -R "$wt/docs/product/delivery/<plan-key>/reviews/"* \
        /path/to/main-clone/docs/product/delivery/<plan-key>/reviews/ 2>/dev/null || true
  cp -R "$wt/.agents/delivery/<plan-key>/handoffs/"* \
        /path/to/main-clone/.agents/delivery/<plan-key>/handoffs/ 2>/dev/null || true
done
```

**Stance:** Treat each **started ticket worktree** as authoritative for continuing its active ticket; treat the **primary `main` copy** as the **aggregate mirror** for full-phase history and closeout. Active-ticket continuation should not require scavenging across older worktrees, but aggregate `reviews/` and `handoffs/` still must be **reconciled across all worktrees**, not only copied from the latest one.

## PR Body Maintenance

PR descriptions are maintained as delivery metadata, not one-shot text.

- `open-pr` creates the initial PR body
- `open-pr` uses a human-readable Conventional-Commit-style title plus the delivery ticket suffix, for example `feat: add user-facing behavior [PN.NN]`
- rerunning `open-pr` refreshes the existing PR title/body instead of failing on an already-open branch
- `record-review` stores the triage result and optional note; when run inside a git checkout it then **stages and commits** the updated `*-pr-review.triage.json` (and the paired `*-pr-review.fetch.json` when present on disk) so the working tree does not stay dirty after a `needs_patch` → `record-review` cycle
- `record-review ... patched` also makes a best-effort attempt to resolve mapped native GitHub inline review threads for patched findings
- `poll-review` auto-records `clean` when no `pr-review` feedback is detected by the final check and refreshes the PR body immediately
- PR-body AI-review notes now distinguish current-head review from stale-history review when the reviewed SHA no longer matches the branch head
- ticket-linked and standalone PR refreshes now share the same reviewer-facing external-review section builder, metadata-refresh adapter, and command-layer persistence helpers while preserving their intentionally different outer PR-body shapes
- `advance` refreshes the PR body from recorded review state, marks the ticket done, then applies the configured `ticketBoundaryMode`
- in `cook`, `advance` auto-starts the next pending ticket and prints the next handoff path
- in `gated`, `advance` stops and prints reset guidance plus the canonical resume prompt; `start` still owns next-ticket handoff creation
- `start` (zero-arg) finds the next pending ticket, creates its worktree and branch, writes its handoff, and prints the handoff path; explicit `start <ticket-id>` form is unchanged

This matters because the repo squash-merges PRs onto `main`, so the PR body needs to mention prudent ai-cr follow-up work before the stack moves on.
