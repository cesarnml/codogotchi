# P19.04 Mode-indicator badge

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A new `FloatingPetWindowControlling` protocol member (mirroring P18.04's `applyPromptTimerPresentation` pattern: default no-op in the protocol extension, so existing test-double conformers compile unchanged) pushes a small, fixed, non-renamable mode-indicator badge — text is the platform display name (for a folded `.origin`) or "Combined" (for `.combined`) — implemented in `FloatingPetPanelController`/`MinimalistPanelController`/`MinimalistBadgeView`.
- The badge is shown exactly when `DesiredWindow.resolvedIdentity != DesiredWindow.key` (P19.01) — never for a solo `.session` window, never for a solo `"default"`-sentinel `.origin` window, always for `.combined`, and for an `.origin` fold only while it's actually folding more than one real session.
- The badge is not user-renamable — no rename affordance is wired to it; it is purely informational, distinct from the live session label (P19.01) shown alongside it.
- Phase retrospective written per Phase Closeout below.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- `MinimalistBadgeViewTests`-style tests: badge text/visibility correct for a `.combined` window; correct for an `.origin` fold with 2+ real sessions; absent for a solo `.session` window; absent for a solo `"default"`-sentinel `.origin` window. A `PoolApplyTests` push-completeness assertion proving the new field reaches the controller (matching the P18.04-tao fix that closed exactly this kind of blind spot for `promptTimerStatus`).
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P19.04): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement the smallest change that makes the failing tests pass
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Verify the badge visibility rule is read directly off `resolvedIdentity != key` — not a re-derived session-count check that could drift out of sync with P19.01's actual data.
- Confirm no rename gesture (click, right-click, or menu item) is wired to the new badge view element — it must stay visually and functionally distinct from the existing renamable session-label badge.
- Check whether the obsolete `SessionLabelStore` fold-global entries (superseded by P19.01's live-resolved label) are worth actively purging in this closing ticket, or are fine left inert — per the implementation plan, this is a judgment call, not a blocking requirement.
- PoolApply/PoolApplyTests push-completeness: confirm the new field is included, mirroring the exact gap the phase-18 `tao` pass found and fixed for `promptTimerStatus`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.

## Phase Closeout

Retrospective: required
Why: Direct architectural sequel to a Phase 18 gap; establishes a durable click-time identity-resolution pattern; reopens the v3 feature freeze as a deliberate, named exception.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-19-fold-window-session-identity-retrospective.md`
