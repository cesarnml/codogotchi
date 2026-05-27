# P9.01 Billing Noise Pre-filter

Size: 2 points
Type: fix
Scope: pr-review

## Outcome

- Running `triage_pr_review.sh` against a fetch artifact that contains only Qodo billing or CodeRabbit account-limit comments produces `outcome: "clean"` and `needs_patch: false`.
- `vendor_status_count` integer field appears in the triage output when at least one comment is classified as vendor noise.
- Comments from `qodo-code-review`, `qodo-merge`, and `coderabbitai` that contain fenced code blocks are NOT classified as `vendor_status` (they may be real findings).
- `bun run ci` is green.

## Red

- Add a test fixture: a minimal `*.fetch.json` containing one comment with `kind: "unknown"`, `authorLogin: "qodo-code-review"`, and body `"You've reached your Qodo monthly free-tier limit"` (no fenced code block).
- Run `triage_pr_review.sh` against the fixture and assert the triage output contains `outcome: "clean"` — before the filter exists the comment still escalates to `needs_patch`, so this assertion fails and produces the required red state.
- Commit with suffix `[red]`: `test(P9.01): billing noise comment escalates to needs_patch [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- In `.agents/skills/pr-review/scripts/triage_pr_review.sh`, before the `$findings`/`$unknowns` JQ stage, add a `vendor_status` pre-filter that removes a comment when ALL of:
  - `kind == "unknown"`
  - `.authorLogin` is in `["qodo-code-review", "qodo-merge", "coderabbitai"]`
  - `.body` does not contain ` ``` ` (no fenced code block)
- Append `vendor_status_count` to the triage output (count of removed comments, defaults to 0).
- Re-run the fixture test — it should now produce `needs_patch: false`.

## Refactor

- Ensure the JQ expression is readable: extract the `vendor_status` predicate as a named JQ variable or comment block.
- No other refactoring.

## Review Focus

- The heuristic must NOT drop a `coderabbitai` comment that contains a fenced code block — those are real review findings.
- The pre-filter must run before `$findings`/`$unknowns` are computed; verify ordering in the JQ pipeline.
- `vendor_status_count: 0` in output is non-breaking for any existing consumer reading triage JSON.
- Check: does `coderabbitai` ever post account-limit messages as `kind: "summary"`? (No — confirmed by P4.01 fetch artifact; summaries use different JQ path. But worth a second look during review.)

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `tools/delivery/test/p9-01.test.ts` proved that a lone `qodo-code-review` billing-limit comment currently triages to `needs_patch` instead of `clean`.
Why this path: Filtering these comments before the unknown-comment escalation preserves the existing triage contract and keeps the change isolated to the review triager while covering the same vendor billing/free-trial noise pattern seen in live PR review.
Alternative considered: body-text matching without vendor scoping was rejected because it would be more brittle and risks suppressing unrelated human or bot comments.
Deferred: `vendor_status` details (individual comment bodies) not surfaced in output — only the count. Full detail belongs to the fetch artifact, not the triage summary.
Contract note: The Red instruction was corrected in-place to assert the intended `clean` outcome, because asserting `needs_patch: true` would have passed on the buggy behavior and skipped the required red failure.
