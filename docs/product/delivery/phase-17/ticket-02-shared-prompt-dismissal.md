# P17.02 Shared prompt/dismissal component

Size: 5 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- Exactly one dismissal observer stack (global monitors + local monitors + resign-active) exists in the app target, owned by (or adjacent to) `FloatingPetPromptCoordinator`; no prompt-presenting surface installs its own monitors.
- Exactly one `[FloatingPetPromptItem]` builder exists, parameterized by window-shape capabilities from the approved matrix; the two `presentHidePrompt` implementations (`FloatingPetInteractionView`, `MinimalistBadgeView`) and the mode-switch pill path resolve into it.
- Views reduce to "present at this anchor with these capabilities" — no per-surface item-list construction remains (`grep -n "FloatingPetPromptItem(" apps/menubar/Sources` hits only the shared builder and tests).
- Table-driven unit tests assert the exact prompt-item titles and order the builder produces for each shape × capability row of `docs/contracts/window-capability-matrix.md` (Own with Prune offer, Minimalist with Hide retitle + Panel Size, Combined, session-keyed variants).
- Full existing suite green; behavior identical to the Phase 16 dogfood build, except drift rows dispositioned `bug` on the prompt surface, which land as separate ledger-flagged commits.

## Red

- Write the table-driven builder tests first: for each shape × capability set from the approved matrix, assert the exact `[PromptItem]` titles and order. They fail because the shared builder does not exist yet.
- Tests are behavior-first: they assert matrix rows (what the user sees per shape), not builder internals.
- Run the test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P17.02): <description> [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Introduce the shared builder and capability parameters; make the table-driven tests pass by construction, matching the current per-surface item lists verbatim (titles, order, conditionality).
- Route both `presentHidePrompt` implementations and the mode-switch pill through the shared builder; collapse their private observer setups into the single dismissal stack.
- If any prompt-surface matrix row is dispositioned `bug`: restore it in a **separate commit** with a review-gap ledger entry, after the convergence commit — never folded into it.

## Refactor

- Delete the dead per-surface item-construction and observer code in the same PR; no dual paths survive.
- Only refactor what you touched — no opportunistic cleanup in `FloatingPetInteractionView` / `MinimalistBadgeView` beyond the prompt seam.

## Review Focus

- Neutrality: diff the builder's per-shape output against the pre-ticket item lists — every title, order, and visibility condition reproduced verbatim; intentional differences appear as capabilities, not lost.
- One stack: verify no surface retains a private global/local monitor or resign-active observer for prompts (this is the bug fixed three times — the whole point).
- Capability parameters map 1:1 to named matrix capabilities; no boolean soup that re-encodes shape identity.
- Restoration commits (if any) are separate, cite their matrix row, and have ledger entries.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
