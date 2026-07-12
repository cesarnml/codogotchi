# Phase 09 Draft — Review Pipeline Reliability

_Drafted: 2026-05-13_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: P3/P4/P5/P6/P7 retrospective recurring pain points + notes/private/2026-05-09-template-drift-old-vs-new.md_

_Note: Skill doc fixes (adversarial subagent prompt, `reviewSubagentOverride` default, `codex-preflight` terminology elimination) were applied directly to main before this phase. `AGENTS.soa.md`, `CLAUDE.soa.md`, and `soa-son-of-anton-ethos/SKILL.md` are already correct._

---

## Thesis

The review pipeline has two recurring reliability failures that have shown up in every phase since P04 and have not been fixed at the source, plus one format-drift risk that was observed directly in P29. None of them is catastrophic — agents work around them manually — but they each add avoidable friction to every delivery session. This phase closes all three in a single focused pass before beta.

One fix is a script change in `triage_pr_review.sh`. One is a small code change in `cli-runner.ts`. One is a two-line doc change. Together they take the review loop from "eventually correct after manual triage" to "correct on the first pass" for the common cases.

---

## The Three Problems

### 1. Vendor billing noise escalates tickets to `needs_patch`

**Recurrence:** P04, P05, P06, P07 — every phase with external AI review (CodeRabbit, Qodo).

**What happens:** CodeRabbit and Qodo post account-limit or monthly-free-tier comments on PRs. The `poll-review` triager has no heuristic to distinguish these from code findings. They escalate the ticket to `needs_patch`. The agent eventually triages them correctly via `record-review clean`, but the escalation costs a manual judgment call and an extra CLI command every time.

**Fix:** In the AI review triager (`soa-pr-review` skill, `triage_pr_review.sh`), add a pre-filter step that classifies known vendor billing/account-limit/service-status comment patterns as non-actionable noise before they reach the findings stage. A comment that matches the billing-noise pattern should be recorded as `vendor_status` and never contribute to `needs_patch` escalation.

Known patterns to target initially:

- "You've reached your monthly free-tier limit" (Qodo)
- "Free usage limit" / "usage limit" (CodeRabbit free tier)
- Any comment from a known reviewer bot login that contains no code-block citations and mentions account, limit, tier, subscription, or upgrade

This is a heuristic — it will not catch every case — but it eliminates the patterns that have recurred in every phase.

### 2. Missing pr-review fetcher surfaced at `poll-review` time, not `open-pr` time

**Recurrence:** P03 (and any fresh consumer repo that hasn't installed `soa-pr-review` skill scripts).

**What happens:** When `prReview` policy is `required` or `skip_doc_only`, the orchestrator calls `.son-of-anton/.agents/skills/pr-review/scripts/fetch_pr_review_comments.sh` during `poll-review`. If the script is absent (the symlink target doesn't exist), the process fails with a cryptic `ENOENT`. This happens _after_ the PR is already open and the review window has started. The operator learns about the configuration problem at the worst possible moment.

**Fix:** In `openPullRequest` in `cli-runner.ts`, add an `existsSync` check against `resolveReviewFetcher()` when `prReview` policy is not `disabled`. If the fetcher script is absent, print a clear warning before the PR opens:

```
Warning: pr-review fetcher script not found at <path>.
poll-review will fail. Either install the soa-pr-review skill scripts
or set prReview to "disabled" in orchestrator.config.json.
```

This is not a blocking error — the operator may want to open the PR and handle review manually. But surfacing it at `open-pr` time gives them the information before they're committed to the review window.

### 3. Template drift guard for `/soa decompose`

**Recurrence:** Observed during P29 decomposition (`2026-05-09-template-drift-old-vs-new.md`).

**What happens:** When decomposing a new phase, agents search for existing ticket files to use as format references. They find older delivery docs under `docs/product/delivery/` and copy their format. Older phases use `Goal / Scope / Exit Condition / Rationale` — not the current TDD `Outcome / Red / Green / Refactor / Review Focus / Rationale` contract. The orchestrator expects the current template; tickets written in the old format create ambiguity at every subsequent review gate.

**Two-point fix:**

- Add one line to `docs/template/overview/start-here.md` under the canonical-templates note: "Always use `docs/template/stubs/ticket.template.md` as the format reference — never model a new ticket on existing docs under `docs/product/delivery/`; older phases predate the current template."
- Add a guard step to the `soa decompose` section of `soa/SKILL.md`: "Before writing any ticket file, read `docs/template/stubs/ticket.template.md`. Do not reference existing ticket files for format."

---

## Out of Scope

- Full programmatic subagent review execution contract (the `runInternalReviewSubagent` phase candidate from `notes/private/2026-05-06-phase-candidate-programmatic-subagent-review.md`). That is a major architectural investment for a future phase.
- `reconcile-late-review` finalize path automation. The manual workaround (`record-review <id> clean <note>`) is functional and documented. Edge case not worth automating for beta.
- `cspell.json` `ignorePaths` template update — direct-to-main patch, included in P10.
- Skill doc fixes (adversarial prompt, `reviewSubagentOverride` default, subagent-review terminology) — applied directly to main before this phase.

---

## Rationale

Items 1 and 2 are code/script changes that stop known recurring interruptions in the review loop. Item 3 is a two-line doc change that closes a known format drift path observed directly in delivery. Together these make the review loop trustworthy for a beta consumer who hasn't memorized the gotchas from seven phases of internal delivery.
