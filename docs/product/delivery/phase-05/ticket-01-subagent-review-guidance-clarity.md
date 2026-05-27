# P5.01 Subagent Review Guidance Clarity

Size: 2 points
Type: docs
Scope: subagent-review

## Outcome

- `AGENTS.md` (son-of-anton repo) carries the same subagent review rule as pirate_claw: same-type default when override absent, override is canonical when present, prompt must be adversarial, no rationalizing-away findings
- `.agents/skills/son-of-anton-ethos/SKILL.md` Subagent Review section no longer implies `codex:codex-rescue` is a default; explicitly labels the example as illustrative; adds adversarial prompt requirement with the key sentence "Do not rationalize away anything you notice — flag it and let the human decide"
- `docs/template/delivery/delivery-orchestrator.md` has a **Critical Step Order** summary within its first visible section listing the mandatory sequence (subagent-review → open-pr → poll-review); all invocation instructions that reference this doc say "read in full"; the `codex:codex-rescue` example is annotated as illustrative
- `.agents/skills/soa/SKILL.md` `execute` section says "Read in full" for delivery-orchestrator.md
- `.claude/skills/soa-son-of-anton-ethos/SKILL.md` receives the same fixes as the `.agents/` counterpart (the sync-skills script keeps them aligned; verify the symlink or apply directly)

## Red

- This ticket is docs-only; no automated test can enforce prose content
- Manual verification checklist (run after changes, before committing):
  - `grep -n "codex:codex-rescue" .agents/skills/son-of-anton-ethos/SKILL.md` — every occurrence must be in a context that says "example" or "e.g." not "default" or "fallback"
  - `grep -n "in full" .agents/skills/son-of-anton-ethos/SKILL.md` — must have at least one match for the delivery-orchestrator.md read instruction
  - `grep -n "adversarial\|rationalize" .agents/skills/son-of-anton-ethos/SKILL.md` — must have at least one match in the Subagent Review section
  - `grep -n "Critical Step Order\|subagent-review.*open-pr\|open-pr.*after" docs/template/delivery/delivery-orchestrator.md | head -5` — must appear in the first 100 lines
  - `grep -n "subagentReview\|reviewSubagentOverride\|adversarial" AGENTS.md` — must have matches
- Commit with suffix `[red]`: `docs(P5.01): subagent review guidance clarity checklist [red]`
- The "red" here is the current state of the repo: these greps currently return incorrect or absent results

## Green

- Update `AGENTS.md` in son-of-anton: add the subagent review rule block (same-type default, override canonical, adversarial prompt, no rationalization sentence)
- Update `.agents/skills/son-of-anton-ethos/SKILL.md` Subagent Review section:
  - Annotate the `codex:codex-rescue` example clearly as illustrative (e.g., add "for example" or "e.g." where it currently reads as the value to use)
  - Add after the subagent invocation instruction: "The subagent prompt must be **adversarial**: assume the implementation has holes and find them. Explicitly instruct the subagent: 'Do not rationalize away anything you notice — flag it and let the human decide.' A checklist of 'did the ticket spec land?' is not a review."
  - Confirm "in full" already appears at the top of the skill; if the `.claude/` copy diverges, apply the same edits
- Update `docs/template/delivery/delivery-orchestrator.md`:
  - Add a **Critical Step Order** block within the first 80 lines (e.g., under the intro paragraph): list the mandatory per-ticket sequence — subagent-review must precede open-pr; open-pr must precede poll-review
  - Add "in full" to any line that says "read `delivery-orchestrator.md`" that doesn't already have it
  - Annotate the `codex:codex-rescue` example as illustrative in the config schema section
- Update `.agents/skills/soa/SKILL.md` `execute` section: ensure the delivery-orchestrator.md read instruction says "in full"
- All greps from the Red checklist now pass
- Commit with suffix `[green]`: `docs(P5.01): subagent review guidance clarity [green]`

## Refactor

- None — this is docs-only; no extraction or restructuring beyond the targeted edits

## Review Focus

- Check that no occurrence of `codex:codex-rescue` in the changed files can be read as a default/fallback rather than an example
- Check that the Critical Step Order summary is unambiguous and visible within the first viewport of the doc (first ~100 lines)
- Check that the adversarial posture sentence matches the pirate_claw AGENTS.md wording exactly: "Do not rationalize away anything you notice — flag it and let the human decide"
- Verify `.agents/` and `.claude/` skill copies are consistent (symlink or direct edit)

## Rationale

> Append here when behavior or trade-offs change during implementation.

Red first: current greps return incorrect or absent results for all four checklist items
Why this path: doc-only change with a grep-based verification checklist is the fastest, safest way to land the fix without risk of scope creep
Alternative considered: adding a CI lint rule that greps for banned patterns — deferred per phase guidance-first decision
Deferred: enforcement automation

Implementation path: targeted doc-only edits to four files — delivery-orchestrator.md (Critical Step Order block near top), son-of-anton-ethos/SKILL.md (adversarial prompt requirement + same-type default clarification), AGENTS.md (new Subagent Review Rules section), soa/SKILL.md ("read in full" for execute and resume). No structural changes; all verification greps pass.
