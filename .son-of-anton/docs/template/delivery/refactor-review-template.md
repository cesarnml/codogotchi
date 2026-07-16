# Refactor Subagent Review Template

This template is filled in by the **primary execution agent** before invoking the refactor-review subagent. It produces the subagent's complete prompt. This gate is a **cold read of the Refactor leg of TDD** — duplication, naming, dead code, complexity, and test-name/behavior alignment. It is not the adversarial correctness/attack-surface gate (`adversarial-review-template.md`); do not blend the two briefs.

**Tag contract:** the subagent reports suggestions inside a literal
`<refactor-suggestions>...</refactor-suggestions>` tag block per
`notes/public/subagent-report-parser-contract.md`. The downstream parser
(`tools/delivery/refactor-review.ts`, `parseRefactorSuggestions`) extracts
only what is between those tags — no heading recognition, no fallback. Copy
the skeleton below verbatim; do not invent a heading-based format.

---

## How to use this template

1. Read the diff against the base branch (`git diff <base>..<head>`).
2. Read the ticket scope (outcome section and rationale).
3. Fill in the **Files touched** and **Local-quality context** sections below.
4. Pass the completed prompt to the subagent verbatim.
5. Stay idle until the subagent completes. Do not read ahead.
6. The primary agent adjudicates each returned suggestion — accept, reject, or defer — with a reason for reject/defer, and records the ledger.

---

## Subagent prompt (fill in before invoking)

```
You are conducting a Refactor-leg cold read of a code change that has already passed
Red and Green (failing test written, then made to pass). Your job is local code-quality
signal on the diff — NOT correctness, NOT invariants, NOT attack surfaces. A separate
adversarial gate covers those; do not duplicate it.

### Ticket scope

<paste the ticket Outcome section and any Rationale notes here>

### Files touched

Implementation:
<list each implementation file changed, one per line>

Tests:
<list each test file changed, one per line>

### Local-quality context

<Paste the relevant diff hunks here, or describe the key logic changes in 3–5 sentences.
Name any areas you specifically want a cold read on (e.g. "this function grew during
Green and may want extraction").>

---

### Your directives

**Scope — local quality signals only:**
- Duplication: repeated logic that could be extracted or reused.
- Naming: identifiers that no longer match what they do after Green.
- Dead code: unreachable branches, unused exports, leftover scaffolding.
- Complexity: functions/branches that grew past what the ticket needed.
- Test-name/behavior alignment: test names that no longer describe what they assert.

Do NOT report: correctness bugs, missing invariants, attack surfaces, security issues, or
architecture opinions beyond the diff at hand. Those belong to the adversarial gate.

**Advisory-only — no file writes:** You must not create, modify, or delete any file in
the repository. Your entire deliverable is findings prose in the required output format
below. The primary execution agent owns all patches.

**No fabrication pressure:** If the diff is already clean on all five signals, your
correct output is a clean report (literal `None` in the tag block below). Do not invent
suggestions to justify the review step.

---

### Required output format

Report in this exact structure (prose only — no file edits).

**Local-quality notes**
For each of the five signals (duplication, naming, dead code, complexity, test-name/
behavior alignment): one line noting what you checked and what you found, or "clean."

**Suggestions**
Copy this tag block verbatim and fill it in. One bullet per suggestion, each naming the
file/function and the specific change. If there is nothing to suggest, the block contains
only the literal word `None` — no bullets, nothing else.

<refactor-suggestions>
- <file/function — specific suggested change>
- <file/function — specific suggested change>
</refactor-suggestions>

**Runner termination**
`runnerStatus`: one of `completed | rate_limit | sandbox_denied | runner_unavailable`.
`terminatedReason`: one short sentence explaining why this status was reported.

`completed` means you finished the review per this template. The other three values are
honest failure modes — the CLI refuses to record `outcome: clean` for any non-`completed`
`terminatedReason`, so do not claim `completed` if you stopped early.
```

---

## Notes for the primary agent

**On adjudication:** you decide per-suggestion whether to accept, reject, or defer. A
reason is required for reject and defer, recorded on the ledger row
(`id`, `summary`, `decision`, `reason`). Accepting a suggestion and patching it commits
with a `[refactor-review]` subject suffix.

**On the subagent model:** Use a different model family from the primary agent when
available — cross-model review breaks shared training-distribution blind spots.
