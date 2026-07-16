# P19.03 Prune confirmation and menu text name the real session

Size: 1 point
Type: feat
Scope: menubar
Red: required

## Outcome

- The Prune context-menu item and its destructive-action confirmation alert (`FloatingPetInteractionView.presentPruneConfirmation`) include the resolved session's identity (platform + label) in their displayed text for a fold window (`.origin` folding multiple sessions, or `.combined`) — e.g. "Prune Session (Claude Code · refactor the diff module)" — instead of a bare "Prune Session" that gives no indication of what's about to be removed.
- For a genuinely solo `.session`-keyed or solo `"default"`-sentinel window, text is unchanged from today — the window is already unambiguous, no extra copy needed.
- No change to Prune's targeting logic (P19.02) or the mode badge (P19.04) — this ticket is copy/UI-text only, reusing data both prior tickets already resolved.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- New `FloatingPetPromptBuilderTests.swift` (no test file exists for this type yet): the built menu item / alert text for a fold window (`resolvedIdentity != key`) includes the resolved session's platform and label; for a non-fold window (`resolvedIdentity == key`) the text is the existing bare form, unchanged.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P19.03): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement the smallest change that makes the failing tests pass
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Confirm the "no fold, no extra text" case is genuinely unchanged — a regression here would add noisy copy to the most common window configuration for no reason, contrary to the phase's stated design.
- Text formatting should degrade gracefully if the resolved session has no LLM-assigned label yet (falls back to whatever `PoolDerive`'s existing fallback chain already produces — session number, known title, or platform display name — not a raw identifier string).
- Intentionally deferred: the mode-indicator badge (P19.04); any change to the destructive-action confirmation mechanics themselves (skip-confirmation preference, alert button structure).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `FloatingPetPromptBuilderTests` (new file) — compile-red on `FloatingPetPromptCapabilities.foldedSessionDisplay` and `FloatingPetHidePrompt.pruneMenuTitle(foldedSessionDisplay:)`, neither of which existed yet.
Why this path: `DesiredWindow` already carries `resolvedIdentity` and a per-tick-resolved `sessionLabel` (P19.01/P19.02) keyed off it, but no view ever learns whether a window is actually folding another identity (`key != resolvedIdentity`) — only `currentSessionLabel`, which is populated the same way for a genuinely solo window too, so it can't disambiguate "no fold" by itself. The smallest fix computes one new formatted field, `DesiredWindow.foldedSessionDisplay` ("`<platform> · <label>`", `nil` when not folding), in `PoolDerive` right after `sessionLabel` is resolved — reusing the exact `resolvedIdentity`/`sessionLabel`/`PlatformAttribution` data those prior tickets already produce — and threads it through the existing `applySessionLabel`-shaped push pipeline (`PoolApply` → `FloatingPetWindowControlling`/`PanelManaging` protocols → `FloatingPetPanelController`/`MinimalistPanelController` → view) to both Own and Minimalist. `FloatingPetHidePrompt.pruneMenuTitle(foldedSessionDisplay:)` is one pure formatter shared by the menu item (`FloatingPetPromptBuilder`) and both `presentPruneConfirmation()` alert bodies, so the two surfaces can never drift.
Alternative considered: computing the fold/platform/label text directly in each view from `currentSessionLabel` plus a new plain `Bool` "isFold" flag was rejected — it would require the same platform-name-vs-label dedup logic to live in two views instead of once in `PoolDerive`, and `currentSessionLabel` already conflates "resolved label" with "own label" so a `Bool` alone wouldn't carry the platform name needed for the ticket's example text.
Deferred: the mode-indicator badge (P19.04, unaffected — reads its own visibility rule off `resolvedIdentity != key`, unrelated to this ticket's text); any change to the confirmation alert's mechanics (skip-confirmation preference, button structure) — untouched.
Contract note: none — `Type: feat`, `Scope: menubar`, `Red: required` all matched the ticket doc.
