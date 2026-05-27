# P9.03 Exit Hygiene & Template Fixes

Size: 2 points
Type: fix
Scope: orchestrator

## Outcome

- `post-verify` prints a non-blocking warning when the working tree has uncommitted changes before recording the outcome. The message lists the uncommitted files. Delivery continues regardless.
- `bun run ci` (spellcheck included) passes with review artifact JSON files present under `docs/product/delivery/*/reviews/`.
- `docs/template/stubs/ticket.template.md` Red section opens with an explicit doc-only exemption: doc-only tickets skip the Red step entirely; no automated test is required or expected.
- `README.md` Install section includes a one-line note to add `docs/product/delivery/*/reviews/**` to `cspell.json` `ignorePaths`.
- Retrospective written to `docs/product/retrospectives/phase-09-review-loop-hardening-retrospective.md`.
- `bun run ci` is green.

## Red

- Add a test: invoke `recordPostVerify` (or the post-verify path) with an injected `hasUncommittedChanges` returning `true` — assert no warning is printed (the warning does not exist yet). This is the failing test.
- Commit with suffix `[red]`: `test(P9.03): post-verify does not warn on uncommitted changes [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

1. **`tools/delivery/cli-runner.ts`** — at the start of the `post-verify` case (before calling `recordPostVerify`), inject `hasUncommittedChanges` (boolean or async fn returning boolean). If true, print:
   ```
   Warning: working tree has uncommitted changes.
   Confirm these are intentional before recording post-verify clean.
   Uncommitted files:
     M <file>
     ...
   ```
   Non-blocking — execution continues. `getWorkingTreeStatus` injectable for unit tests (returns empty string or `"M src/foo.ts"` as needed).
2. **`cspell.json`** — add `"docs/product/delivery/*/reviews/**"` to `ignorePaths`.
3. **`docs/template/stubs/ticket.template.md`** — prepend to the Red section body:
   > **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step entirely. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**
4. **`README.md`** — in the Install section, after the `.prettierignore` guidance line, add:
   ```
   Add `docs/product/delivery/*/reviews/**` to your `cspell.json` `ignorePaths` to prevent spellcheck failures on review artifacts.
   ```
5. **Retrospective** — after final PR is approved and merged, use the `soa-write-retrospective` skill to write `docs/product/retrospectives/phase-09-review-loop-hardening-retrospective.md`.

## Refactor

- No refactoring needed. All changes are additive.

## Review Focus

- Uncommitted-changes warning: must be non-blocking in all cases — a `throw` here would break every existing `post-verify` call.
- `cspell.json` glob: verify the pattern `docs/product/delivery/*/reviews/**` covers both `*.fetch.json` and `*.triage.json`. Confirm no legitimate files in that path are silently ignored by mistake.
- Ticket template wording: the doc-only note should read as instructional to an AI agent, not just a human. It must be unambiguous: "skip the Red step entirely" — not "may skip" or "consider skipping".
- README note: check it appears in the correct Install section and does not duplicate any existing guidance.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: blocking the warning (throwing on uncommitted changes) — rejected; too disruptive for common workflows where the agent intentionally has staged-but-uncommitted work.
Deferred: surfacing specific uncommitted file details in the warning body is best-effort — implementation may omit the file list if the DI pattern makes it complex; the warning text alone is the minimum requirement.
Contract note: [record any deviation from the ticket metadata contract here]
Contract note: the Outcome and Green sections require a non-blocking uncommitted-changes warning, while the Red section says to assert that no warning is printed. Red follows the intended behavior contract from Outcome/Green, so the failing regression expects the warning and treats the Red bullet as contradictory metadata.
Red first: `tools/delivery/test/p9-03.test.ts` failed because `recordPostVerify` advanced the ticket without emitting any uncommitted-changes warning.
Why this path: threading the warning through `recordPostVerify` with injectable status readers kept the behavior testable without changing the broader command contract or making `post-verify` blocking.
