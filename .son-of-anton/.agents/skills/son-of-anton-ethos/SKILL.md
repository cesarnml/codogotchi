---
name: soa-son-of-anton-ethos
description: Execute approved multi-ticket phase/epic work or standalone (non-ticketed) PR delivery through the repo orchestrator with strong continuation bias. Use automatically when a user asks to execute, begin, start, deliver, implement, continue, resume, run, drive, carry, or work on a phase, epic, or standalone PR, or explicitly mentions son of anton or son-of-anton ethos.
---

# Son Of Anton Ethos

**Before executing a single command:** Read `docs/template/delivery/delivery-orchestrator.md` in full. Every orchestrator action — for both ticket stacks (`start`, `post-verify`, `write-subagent-adversarial-review`, `subagent-review`, `open-pr`, `poll-review`, `record-review`, `advance`, `triage-ticket`) and standalone PRs (`triage-standalone`) — is defined there with exact sequencing and policy. That document is the authoritative command surface. Your own reasoning about what the flow "probably" is does not override it.

Son of Anton drives approved work to completion. How ticket boundaries are handled is governed by `ticketBoundaryMode` in `orchestrator.config.json`. The orchestrator does not seek repeated permission between tickets — but it honors the boundary contract precisely as configured.

---

## Standalone PRs

1. **Entrypoint.** Use `bun run deliver`.
2. **When to use.** Smaller bounded changes ship as standalone PRs without a new phase/epic. Use `bun run deliver triage-standalone [--pr <number>]` — not the ticketed stacked flow (`--plan …`, `poll-review`, `advance`, etc.).
3. **Review discipline.** Complete implement → fast verification (`bun run verify:quiet` + scoped tests as needed) → final publication gate (`bun run ci:quiet` for non-doc code changes) → named self-audit (re-read diff, second-pass risky areas). Standalone PRs do not use the ticket-only `post-verify` or `subagent-review` recorders because the flow is stateless, so these remain expected preflight behaviors rather than orchestrator-enforced gates.
   - Self-audit is required for every standalone PR.
   - For non-trivial code changes, invoke a review subagent via the Agent tool before `triage-standalone`. Fill in `docs/template/delivery/adversarial-review-template.md` from the diff and use it as the prompt — do not substitute a vague "find holes" directive. Doc-only or genuinely trivial changes may skip this step.
   - Standalone `triage-standalone` is the only orchestrator-visible review gate on this path.
   - If the change needs recorded self-audit / Codex gates to feel safe, it likely should not stay a standalone PR unless the repo first adds lightweight standalone review state.
4. **Running `triage-standalone`.** Uses real wall-clock polling. Surface that before starting; do not hide the time cost.
5. **Commits.** Follow AGENTS Pre-Commit (Prettier for touched files; spellcheck when docs or user-facing copy changed).
6. **Product-scope gates** apply to new phase/epic work — not to standalone PRs already allowed outside a new phase.

---

## Phase / Epic Delivery

### Core Stance

Treat the whole approved phase or epic as the unit of work — not a single ticket unless the user explicitly narrows scope.

When the user asks to execute, begin, start, deliver, implement, continue, resume, run, drive, carry, or work on a phase, that is standing approval to advance ticket-by-ticket without re-invocation between tickets.

**Expected completion state:** every ticket reaches `done` and the developer receives a final summary.

These are normal milestones, not permission checkpoints: one ticket implemented, one PR opened, one review window finished, a natural checkpoint, elapsed time. The workflow is not complete until the full stack is done or a repo-valid stop condition applies.

### Pre-Flight Sequencing

Commit the delivery plan and all ticket docs to the default branch before creating any ticket branches or worktrees. Ticket worktrees depend on those docs at creation time.

### Required Behavior

1. Re-read required repo docs at each ticket boundary. For ticket `01`, use the implementation plan, the ticket doc, and current repo state as the initial handoff context; for later tickets, re-read the handoff artifact materialized into the started ticket worktree as the source of truth.
2. Use the supported orchestrator path, not ad hoc manual substitutes.
3. Move one ticket at a time in order.
4. For each ticket:
   1. For code tickets, write the failing behavior test and commit it with a `[red]` suffix
   2. Run `post-red` before implementation; tickets with no testable behavior declare `Red: skip`, and doc-only branches skip structurally
   3. Implement
   4. Build / verify — use the repo's fast verify command for the inner loop, then the full CI command before `open-pr` on code tickets
   5. Update ticket rationale for behavior or tradeoff changes
   6. Self-audit — `post-verify [clean|patched]`
      - Under `subagentReview: "skip_doc_only"`: doc-only tickets auto-record `skipped`
      - Under `subagentReview: "required"`: doc-only tickets still need an explicit `clean` or `patched`
   7. Author subagent prompt — `write-subagent-adversarial-review` when `subagentReview` is not `"disabled"` (see [Subagent Review](#subagent-review)). The primary agent fills `docs/template/delivery/adversarial-review-template.md`; the subagent does not author its own brief.
   8. Subagent adversarial review — `subagent-review` with `--subagent` when programmatic review is required. Runner artifacts are committed and pushed by the orchestrator; do not add a second manual commit for those files unless you changed something else in the same step.
   9. Reconcile ledger vs git — `reconcile-subagent-review` before `open-pr` (hard-blocks silent lies; see delivery-orchestrator.md)
   10. Open / refresh PR — `open-pr`
   11. Run AI-review polling — `poll-review` (see [External Review](#external-review))
   12. Patch prudent findings
   13. Record review — `record-review` (**skip** when `poll-review` already auto-recorded `clean` or `skipped`; only needed when `poll-review` leaves ticket in `needs_patch` state). The orchestrator commits updated `*-pr-review.{fetch,triage}.json` after a successful `record-review` when the ticket worktree is a git checkout — do **not** add a second manual commit for those files unless you changed something else in the same step.
   14. Advance — `advance`
5. During the external review window, stay idle.
6. Do not write ahead across ticket boundaries.
7. After `advance`, follow the active boundary mode and keep going without asking for permission unless a real blocker exists.

### Ticket Boundary Modes

Treat `ticketBoundaryMode` in `orchestrator.config.json` as the contract for ticket-boundary behavior.

- `cook`: default Son-of-Anton path. `advance` immediately starts the next ticket. Read the handoff materialized into the started worktree and continue.
- `gated`: `advance` stops, tells the operator to reset context, and prints the canonical resume prompt for the next agent session. Prefer `/clear`; use `/compact` only when compressed carry-forward context is intentional.
- `glide`: reserved/unimplemented — currently falls back to `gated` in repo-local code. Do not assume self-reset capability.

Canonical `gated` resume prompt:

`Immediately execute \`bun run deliver --plan <plan> start\`, read the locally materialized handoff artifact in the started worktree as the source of truth for context, and implement <next-ticket-id>.`

**After `advance` in `gated` mode, you must echo the resume prompt as the final human-visible output — not buried in CLI output, not paraphrased.** Format it exactly like this, substituting the real plan path and next ticket id:

```
P<N>.<NN> is done. PR: <url>

Reset context (/clear), then resume with:

/soa resume phase-<NN>
```

### Subagent Review

**Role split:**

- **Primary agent** executes and patches (build mode and post-verify), and also applies patches for findings the review subagent returns. Patches applied in response to subagent findings are committed by the primary agent with a `[subagent-review]` subject suffix.
- **Review subagent** is an advisory runner — a second AI pass before the PR is published. It reports blocking `Actionable findings` for broken invariants, demonstrable correctness gaps, or spec-permits-real-bug cases, and reports non-blocking off-scope-but-real notes under `Advisory Observations`. It does not own patch application; the primary agent decides what to patch and commits it. Exactly one `subagent-review` invocation per ticket via programmatic subprocess; repeat invocations against the same HEAD are no-op recorders.
- **External AI vendors** (e.g. CodeRabbit, Qodo) review post-publication via `poll-review`.

**When `subagentReview` is `"required"` or `"skip_doc_only"` (code tickets):**

1. **Read `docs/template/delivery/adversarial-review-template.md`.** Fill in the template from the current diff and ticket spec — invariants, attack surfaces (including the seven diff-derived classes), diff context. This takes real work; do not skip it or pass a vague prompt.
2. **Record the prompt:** `bun run deliver --plan <plan> write-subagent-adversarial-review` (or `--prompt-file` when the filled template already exists on disk). The primary agent authors the brief; the subagent never fills the template itself.
3. Invoke the advisory review subagent **exactly once per ticket** via programmatic subprocess: `subagent-review` with `--subagent <claude-cli|codex-cli|cursor-cli>`. The CLI sends the persisted prompt bytes, tries the preferred runner first, falls back to the other programmatic runners, and records an honest `skipped` artifact if none are available. Use a different model family from the primary agent when available (cross-model review breaks shared blind spots).
4. **Stay idle. No read-ahead.** Wait for the runner subprocess to exit before doing anything else — same discipline as the external review window.
5. The runner returns findings prose only — it must not modify the worktree. If it does, the CLI records `advisory_violation`, not a completed clean review. The **primary agent** reads findings, applies any prudent patches (commit with `[subagent-review]` suffix), records deferral (`subagent-review record-deferred --reason "..."`), or leaves a genuinely clean result. Then record: `bun run deliver --plan <plan> subagent-review [clean|patched|deferred] <sha...>`. Run `reconcile-subagent-review` before `open-pr`; the gate also runs inside `open-pr` and accepts `--ack-reconciliation` when the operator explicitly acknowledges the ledger state.

Without `--subagent`, the CLI is a state recorder only and does not invoke a runner. With `--subagent`, the CLI invokes the runner against `reviews/<ticket>-subagent-review.prompt.md`, persists runner prose to `reviews/<ticket>-subagent-review.report.md`, and writes `reviews/<ticket>-subagent-review.ledger.json` with path references in `filledPrompt` and `rawOutput` (not embedded text). The artifact carries the runner's `terminatedReason`; the CLI refuses to record `outcome: clean` for any non-`completed` terminatedReason.

**Subagent scope contract:** The review subagent is advisory-only — it reports findings and must not write files. The primary agent applies any resulting patches. Ticket doc files under `docs/product/delivery/` are primary-agent delivery artifacts; the subagent reads them for drift probing and surfaces non-blocking mismatches in **Advisory Observations** only. The template encodes these constraints; do not remove them.

**When `subagentReview` is `"skip_doc_only"`** (repo default): code tickets still require the subagent step before `open-pr`; doc-only tickets auto-record `skipped`.

**When `subagentReview` is `"disabled"`**: skip the step entirely.

If the configured subagent is unavailable, set `subagentReview: "disabled"` in `orchestrator.config.json` to bypass the gate.

---

## External Review

Applies to standalone PRs (`triage-standalone`), in-review ticket stacks (`poll-review`), and done ticket-linked PRs (`triage-ticket`). The review signals and triage rules are the same; only the CLI command differs.

### Signals

- **Inline review threads** are the signal for CodeRabbit and Greptile. Their summary PR comments are orchestration noise — ignore them.
- **Qodo** posts a single actionable PR comment with all findings — treat it as actionable when present.
- **SonarQube** posts a Quality Gate summary PR comment; check-run annotations are secondary signal.

For ticket stacks, the orchestrator persists vendor evidence in `reviews/<ticket>.fetch.json` and repo-local judgment in `reviews/<ticket>.triage.json`. `state.json` is only an index into those artifacts, not the source of truth for comment payloads.

### Outcome Recording

Record `clean` only when no actionable feedback found. Record `patched` when actionable feedback was prudently fixed. Do not downgrade `patched` to `clean` because later polling is quiet.

### Docs-Only PRs

With the repo default `skip_doc_only` policy, doc-only tickets skip the external review window and record `skipped` immediately. When a stage is `required`, doc-only tickets wait/run like code tickets.

---

## Stop Conditions

Stop only for: unsafe work, missing prerequisites not resolvable from repo context, ambiguous review triage genuinely needing developer judgment, broken delivery state that cannot be prudently repaired, an explicit documented control point, or explicit user interruption.

If none of those are true, continue.

## Anti-Pattern

Do not use these as stopping points for approved stacked delivery:

- returning control after one ticket with "I finished the current ticket"
- treating an open PR as completion
- treating a running or clean review as completion
- pausing to ask whether to continue when no stop condition exists
- offering a mid-run progress summary and waiting for acknowledgment

## Response Rule

If blocked, report: the exact ticket, the exact blocker, the exact repo policy reason that forced the stop. Send a Telegram notification with that info and a link to the relevant doc.

If not blocked, keep executing.

## On Phase or Epic Completion

Write the retrospective to `docs/product/retrospectives/<plan-path>-retrospective.md` using the `soa-write-retrospective` skill at `.agents/skills/write-retrospective/SKILL.md` for section structure and placement conventions.
