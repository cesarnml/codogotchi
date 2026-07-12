---
name: soa-pr-review
description: Detect and triage AI-generated pull request review comments for the delivery orchestrator flow. Use when poll-review finds AI review feedback or when you need to inspect recent AI review comments on the current PR.
---

# AI Code Review

Supported external review agents: `coderabbit`, `qodo`, `greptile`, `sonarqube`. Other vendors are unsupported unless repo policy adds them.

## Boundary

The orchestrator owns polling cadence, state transitions, artifact persistence, and auto-recording `clean` on the final check. After `record-review`, it also **git-commits** the updated review JSON artifacts when running in a normal git checkout so the triage file is not left dirty on disk.

This skill owns: fetching review data with `gh`, detection logic, normalizing comments into structured artifacts, and triage judgment.

Contract:

- fetcher outputs: `detected`, `agents`, `reviewed_head_sha`, `vendors`, `comments`
- triager outputs: `outcome` (`clean|needs_patch|patched`), `note`, `action_summary`, `non_action_summary`, `vendors`

When triager returns `needs_patch`, follow-up must conclude as `patched` or `operator_input_needed` — not stop permanently at `needs_patch`.

## Workflow

1. Resolve PR number with `gh pr view` if not provided.
2. Fetch with `.agents/skills/pr-review/scripts/fetch_pr_review_comments.sh <pr-number>`.
3. If orchestrator already saved `review.fetch.json`, use that as the source of truth for vendor attribution and comment shape.
4. Detection policy: supported vendor identities, explicit vendor wording in comment body, check-run annotations. Human drive-by comments do not count. Preserve head SHA, inline resolution/outdated state, and native thread identity.
5. Return fetcher contract when inside `poll-review`: `detected=false` → keep polling or auto-clean; `detected=true` → orchestrator inspects agent state and decides.
6. Triage each detected comment: actionable, stale, wrong, over-scoped, or out of scope.
7. Treat AI review as advisory, not authoritative.
8. Push back on stale, over-scoped, unnecessary, or policy-conflicting suggestions.
9. When running as triager hook, return the triager contract and let the agent environment decide whether to patch or stop.
10. If user approves a patch: apply it, run the smallest relevant verification, commit, push. If the finding came from a native GitHub inline thread still resolvable, mark it resolved.

## Output Expectations

- State whether AI review comments were found.
- Filter summary noise; focus on unresolved review items.
- Group by unresolved issue, not raw API payload.
- Include file and line when available.
- Distinguish current-head review from stale-history review when reviewed SHA no longer matches branch head.
- State which comments are actionable and which should be rejected.
- Call out stale or already-addressed comments rather than blindly implementing them.
- Stop for operator input only when the right action is genuinely ambiguous.
