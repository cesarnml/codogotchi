# P11.02 Adversarial template expansion and ethos advisory-runner correction

Size: 3 points
Type: docs
Scope: delivery

## Outcome

- `docs/template/delivery/adversarial-review-template.md` contains a new "Diff-derived attack surfaces" sub-section under "Attack surfaces" that enumerates, by name, the seven absorption-target finding classes from the product plan: output stability across schema-version drift, CLI flag/arg symmetry, error-class breadth in `catch` blocks, defensive layering at module boundaries, cross-file atomicity windows, test-contract strength, and doc-vs-code drift in the ticket Rationale. Each surface uses the coverage-mandate output form (`[probed]` / `[N/A — reason]` / `[blocked — missing-input]`).
- The template's scope contract is relaxed from "skip ticket docs" to "do not patch ticket docs; do read the Rationale and contract docs and surface doc-vs-code drift in Findings for human review."
- The "Patch discipline" directive includes a third patch-when clause: patch when the ticket's stated contract literally permits a behavior that is nevertheless unsafe in production (the "spec-permits-real-bug" case).
- The template requires the subagent to emit a `runnerStatus` / `terminatedReason` field as part of its mandatory output, with allowed values `completed | rate_limit | sandbox_denied | runner_unavailable`.
- The `son-of-anton-ethos` skill text (at the path resolved by `soa-sync` — typically `.agents/skills/son-of-anton-ethos/SKILL.md` and/or the source under `docs/template/`) describes the advisory-runner contract correctly: `subagent-review` returns findings; the primary agent applies patches and commits them with `[subagent-review]` suffix; exactly one `subagent-review` invocation per ticket via programmatic subprocess.
- `bun run ci` is green; spellcheck includes any new terminology.

## Red

- **Doc-only ticket — skip Red.** Branch touches only `.md` files. No automated test required.

## Green

- Edit `docs/template/delivery/adversarial-review-template.md`:
  - Add the "Diff-derived attack surfaces" sub-section beneath the existing "Attack surfaces" section. Name each of the seven classes explicitly. Include the coverage-mandate output form for each.
  - Update the scope contract paragraph to the flag-only-doc-drift wording.
  - Append the "spec-permits-real-bug" clause to "Patch discipline."
  - Update the required-output section to include `runnerStatus` / `terminatedReason` with the four allowed values.
- Edit the ethos skill source (the canonical one tracked under `docs/template/` — `soa-sync` is responsible for distributing it). Remove the "reviews and patches its own findings autonomously" claim. Replace with the advisory-runner contract.
- Add any new terminology to the spellcheck allowlist if `bun run verify` flags it.

## Refactor

- Skim the rest of the template for now-stale phrasing that contradicts the new sub-section. Fix only contradictions; leave style cleanup alone.

## Review Focus

- Whether the seven-class enumeration is unambiguous to a future subagent reading cold. Each class needs enough definition that "[probed]" is verifiable, not aspirational.
- The doc-drift relaxation must be unambiguous about flag-only-not-patch — the subagent must not start editing ticket docs.
- Ethos correction wording — confirm it matches actual CLI behavior at HEAD before P11.03 lands (the contract is advisory _now_, even before the recorder-mode change).
- Spellcheck/lint may flag new terms (`runnerStatus`, `terminatedReason`, `sandbox_denied`); update the allowlist deliberately.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: docs-only ticket — no Red step per the canonical template.
Why this path: kept the seven diff-derived classes named one-per-numbered-block with the coverage-mandate output form repeated per class. Future subagents reading the template cold need each class to be its own probe target, not a comma-separated list embedded in prose. The scope-contract relax was rewritten in two paragraphs so the "do not patch / must still read" split is unambiguous, and the patch-discipline clause was rewritten as a numbered list so the new spec-permits-real-bug case is visually parallel with the existing two.
Alternative considered: a single bullet list per class with one shared output-form footer at the bottom. Rejected — easy for a subagent to skip the footer when copying its report structure from the class definitions.
Deferred: the recorder-mode CLI behavior (artifact-existence-at-HEAD idempotency, operator-supplied outcomes skipping subprocess invocation) and runner-termination honesty (CLI refuses `clean` for non-`completed` `terminatedReason`) ship in P11.03 and P11.04 respectively. The ethos doc references those contracts as the target state; the runner artifact already carries `terminatedReason` after P11.01.
Contract note: ethos skill update touched `.agents/skills/son-of-anton-ethos/SKILL.md` (the actual source tracked in git). The ticket Outcome's "or the source under `docs/template/`" alternative path does not exist in this repo; `soa-sync.sh` reads from `.agents/skills/` directly.
