# Phase 09: Review Loop Hardening

_Merged from: `phase-09-review-pipeline-reliability.md` + `phase-10-tdd-gate-hardening.md`_

**Delivery status:** Decomposed — delivery tickets written. Ready to execute.

## TL;DR

**Goal:** Close two quality-gate gaps in the delivery loop — vendor billing noise that escalates tickets to `needs_patch`, and a TDD gate that accepts a "[red]" commit subject as proof without verifying any test actually failed.

**Ships:**

- Billing-noise pre-filter in `triage_pr_review.sh`: classifies known vendor account-limit/free-tier comments as `vendor_status` (bot login + no code-block citations) and excludes them from `$findings`/`$unknowns`. Never triggers `needs_patch`.
- `post-red` CLI command: records HEAD commit SHA, asserts `[red]` in subject, runs `verify`/`ci` and confirms at least one test fails, advances ticket status to `red_complete`. Doc-only branches skip this gate automatically.
- `isLocalBranchDocOnly` expansion: add `.json` to the doc-only extension list alongside `.md`. A branch that only touches `.json` files (e.g. `cspell.json`, config) is doc-only and skips the `post-red` and review gates.
- Uncommitted changes warning in `post-verify`: `git status --porcelain` check, non-blocking.
- `cspell.json` `ignorePaths` update: add `docs/product/delivery/*/reviews/**` to prevent review artifact spellcheck failures on every new consumer's first code ticket.
- Ticket template: Red section explicitly states "Skip the Red step for doc-only branches (branch touches only doc-only files). No automated test is required or expected for pure doc changes."

**Defers:** Full `post-red` failure attribution (which tests failed, line counts); review artifact atomic commit with `advance`; `reconcile-late-review` finalize-path automation; full programmatic subagent review execution; `.yaml`/`.yml` addition to doc-only extension list.

---

This phase merges two pre-planning drafts. The review loop has two compounding reliability failures: billing noise from external review vendors escalates every phase's first PR to `needs_patch` (confirmed P04–P07, four consecutive phases), and the TDD red gate has no machine-readable proof that a test actually failed — the "[red]" commit subject is a convention any agent can satisfy without running tests. Both are fixable in this phase without over-engineering either.

Two related items come along: `isLocalBranchDocOnly` currently treats `.md`-only branches as doc-only, but `.json`-only changes (config, cspell, ignorePaths) are equally not code work and should skip the same gates. And demanding a failing test on a pure doc ticket is theater — tests asserting exact wording in SKILL.md or ticket docs couple the test suite to legitimate rewrites with no real quality signal. The correct gate for doc changes is human review; automated tests add brittleness, not confidence.

Pre-phase patches already applied to main: template drift guard (`start-here.md` + `soa/SKILL.md` decompose step), adversarial subagent prompt, `reviewSubagentOverride` default. Not in scope here.

## Phase Goal

This phase should leave the product in a state where:

- A PR whose only external AI review comments are vendor billing/account-limit messages produces `outcome: "clean"` without manual `record-review clean` intervention.
- An agent cannot satisfy the `post-red` gate by writing a "[red]" commit message without a failing test; the orchestrator verifies the test run failed before advancing to `red_complete`.
- A branch that only touches `.json` files is classified as doc-only and skips `post-red`, subagent review, and PR review gates — consistent with `.md`-only branches today.
- Doc-only tickets have no automated test requirement; the ticket template and `post-red` gate both reflect this explicitly.
- `bun run ci` is green.

## Committed Scope

### 1. Billing-noise pre-filter in `triage_pr_review.sh`

Add a pre-filter to the JQ expression in `.agents/skills/pr-review/scripts/triage_pr_review.sh` before the `$findings`/`$unknowns` stage.

A comment is `vendor_status` if:

- `kind == "unknown"` (findings are never billing noise), AND
- `authorLogin` is in the known billing-bot set: `qodo-code-review`, `qodo-merge`, `coderabbitai`, AND
- body contains no fenced code block (no ` ``` `)

Rationale: billing copy changes; bot login + absence of code citations does not. Qodo bots only post billing messages as `unknown`-kind comments — the bot login alone is sufficient. The no-code-block guard adds specificity for `coderabbitai`, which also posts walkthrough summaries — but those are classified as `kind: "summary"` by the fetcher and never reach this filter (confirmed by P4.01 fetch artifact).

`vendor_status` comments never contribute to `needs_patch`. The triage output adds an optional `vendor_status_count` integer field. Non-breaking for existing consumers.

### 2. `post-red` CLI command

```bash
bun run deliver --plan <path> post-red [ticket-id]
```

Behavior:

1. Resolves the target ticket (active `in_progress` ticket if `ticket-id` omitted).
2. If the branch is doc-only (per `isLocalBranchDocOnly` after the `.json` expansion below): print `"Doc-only branch — post-red skipped."` and exit clean. No state change.
3. Asserts HEAD commit subject contains `[red]`.
4. Runs the repo's `verify`/`ci` command (via the `runVerify` DI hook) and asserts non-zero exit (at least one failure).
5. Records `redCommitSha` on the ticket and advances status to `red_complete`.

New ticket status: `red_complete` (between `in_progress` and `verified`).
New field on `TicketState`: `redCommitSha?: string`.

Updated status machine:

```
pending → in_progress → red_complete → verified → subagent_review_complete → in_review → reviewed → done
```

`post-verify` requires `red_complete` as a prerequisite for code tickets. Doc-only tickets skip `red_complete` (same pattern as `subagentReview` skipping).

DI: `runVerify` override injectable for unit tests (same pattern as `hasLocalBranchCommits`'s `runProcessOverride`). No real CI execution in unit tests.

### 3. `isLocalBranchDocOnly` expansion to include `.json`

In `tools/delivery/platform.ts`, extend the doc-only extension list:

```diff
- return files.length > 0 && files.every((f) => f.endsWith('.md'));
+ return files.length > 0 && files.every((f) => f.endsWith('.md') || f.endsWith('.json'));
```

Rationale: a branch that only touches `cspell.json`, `orchestrator.config.json`, or `renovate.json` is config/doc work. It should skip `post-red`, subagent review, and PR review — the same as `.md`-only branches. The existing semantics protect against false positives: the function only returns true when ALL changed files match; a ticket touching both `cspell.json` and `platform.ts` is still classified as code.

### 4. Uncommitted changes warning in `post-verify`

At the start of `recordPostVerify` (in `tools/delivery/cli-runner.ts`), if `git status --porcelain` returns non-empty output, print:

```
Warning: working tree has uncommitted changes.
Confirm these are intentional before recording post-verify clean.
Uncommitted files:
  M src/foo.ts
```

Non-blocking. Operator or agent decides whether to commit first. `getWorkingTreeStatus` override injectable for unit tests.

### 5. `cspell.json` `ignorePaths` update

Add `docs/product/delivery/*/reviews/**` to `ignorePaths` in `cspell.json` at the repo root. This prevents review artifact JSON files (`*.fetch.json`, `*.triage.json`) from triggering spellcheck failures — a failure mode that hit P7 mid-phase and will hit every new consumer on their first code ticket.

Also add a one-line setup note in `README.md`'s Install section alongside the existing `.prettierignore` guidance: "Add `docs/product/delivery/*/reviews/**` to your `cspell.json` `ignorePaths`."

### 6. Ticket template: doc-only Red exemption

In `docs/template/stubs/ticket.template.md`, update the Red section to open with:

> **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step entirely. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**

The remainder of the Red section (failing test, `[red]` commit) applies to code tickets only.

## Explicit Deferrals

- **`post-red` failure attribution** — which tests failed, failure counts, affected files. The only assertion needed is "at least one test failed." Detailed attribution belongs to the agent reading the output.
- **Review artifact atomic commit with `advance`** — flagged in P6 retro; requires changes to the advance boundary model. Deferred.
- **`.yaml`/`.yml` in `isLocalBranchDocOnly`** — same rationale as `.json` but is scope creep for this phase.
- **Full programmatic subagent review execution** — major architectural investment, future phase.
- **`reconcile-late-review` finalize-path automation** — manual workaround is functional and documented.
- **`openPullRequest` fetcher-existence warning** — investigated and dropped. All "missing" fetch files in `.agents/delivery` are doc-only policy skips, confirmed by triage artifact content. No recurring failure exists.

## Exit Condition

- A PR with only Qodo billing or CodeRabbit account-limit comments → `poll-review` outcome `clean`, no manual intervention.
- An agent that commits `[red]` without a failing test → `post-red` rejects (test run exited 0).
- A branch touching only `cspell.json` → classified doc-only, skips `post-red` and review gates.
- `bun run ci` green.

## Retrospective

`required` — Phase introduces a new status in the delivery state machine (`red_complete`), a new CLI command (`post-red`), a hard gate in `post-verify`, and a doc-only classification expansion. These are durable changes to the orchestrator contract worth documenting.
