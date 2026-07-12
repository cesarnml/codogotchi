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

Red first: `FloatingInteractionTests` table-driven builder tests referencing
`FloatingPetPromptBuilder`/`FloatingPetPromptCapabilities`/
`FloatingPetPromptHandlers` — none of those types existed yet, so the suite
failed to compile.

Why this path: two convergence seams, not one — (1) a pure
`FloatingPetPromptBuilder.items(capabilities:handlers:)` producing
`[FloatingPetPromptItem]`, parameterized by a `FloatingPetPromptCapabilities`
struct whose fields map 1:1 to named matrix rows (`offersForceIdle`,
`sessionLabel`, `hasActiveSession`, `modeSwitchTitle`, `offersPanelSize`,
`hideItemTitle`) rather than a shape-identity boolean; and (2) a
`FloatingPetPromptDismissal` class (adjacent to `FloatingPetPromptCoordinator`
in `Windows/`) owning the global-mouse/local-mouse/global-keyboard/
resign-active monitor stack, reused by all three surfaces that previously
hand-rolled it: `FloatingPetInteractionView`'s hide prompt, `MinimalistBadgeView`'s
hide prompt, and `MinimalistBadgeView`'s panel-size pill — "the bug fixed
three times" the ticket's Review Focus calls out. `NSWindow.didResignKeyNotification`
(R1.11, confirmed dead code — both panels are non-activating and never become
key) was dropped from the shared stack rather than carried forward.

Alternative considered: a `shape: .own | .minimalist` enum parameter on the
builder instead of named capability fields. Rejected — it re-encodes shape
identity as a boolean/enum, which the ticket's Review Focus explicitly
prohibits ("no boolean soup that re-encodes shape identity"), and it would
make a future capability that varies independently of shape (none exist
today, but the matrix format anticipates them) awkward to express.

Deferred: nothing — all 33 matrix rows for §1 (prompt items) were
dispositioned `intentional` with none `bug`, so there is no drift-restoration
commit in this ticket. `MinimalistPanelController`/`FloatingPetPanelController`
chrome-flock convergence stays out of scope per the ticket order (P17.03).

Contract note: none — `Type: refactor`, `Scope: menubar`, `Red: required` all
matched the actual work.
