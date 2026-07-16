# P21.01 Delete shadow trio + husk; scrub false P18 “not yet” comments

Size: 2 points
Type: chore
Scope: menubar
Red: skip

## Outcome

- `PoolShadowComparator`, `RecordingFloatingPetWindowControllingProxy`, and `ShadowDivergenceLogger` no longer exist under `apps/menubar/Sources/` (or anywhere else in the menubar app target).
- Dedicated tests that exist only to exercise that harness (`PoolShadowComparatorTests`, `RecordingFloatingPetWindowControllingProxyTests`, `ShadowDivergenceLoggerTests`, and any other orphaned-only callers) are removed; no stub empty files remain that imply live shadow architecture.
- `apps/menubar/Menubar.xcodeproj` husk is deleted; `Codogotchi.xcodeproj` / xcodegen remains the real project.
- Doc comments under `apps/menubar/Sources/` that falsely claim unfinished P18.0x work (e.g. “Always empty until P18.03”, “does not yet emit `promptTimerStatus`”, “still unwired into the live tick (P18.05)” while presentation is already pushed) are rewritten to present-tense truth. Accurate P18 provenance archaeology may remain.
- Full existing suite green aside from removed harness tests; project builds.

## Red

- `Red: skip` — delete-only + comment scrub; no new testable behavior. Absence is proven by post-green grep and the remaining suite, not a failing “type must not exist” red.

## Green

- Delete the three shadow source files and their dedicated test files; update any incidental references.
- Delete `apps/menubar/Menubar.xcodeproj`.
- Scrub false present-tense P18 comments across `Sources/` (Derive + Windows timer docs and any other lies). Leave accurate historical provenance.
- Regenerate / build as needed; run suite.

## Refactor

- None beyond the deletions and comment edits. Do not start fold-display, timer-protocol, or allocator work.

## Review Focus

- Confirm zero remaining production or test references that require the deleted types.
- Comment scrub killed **lies**, not every P18 ticket mention — step maps that are still accurate stay.
- No behavior changes to pool update path, prune, or timers.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Red: skip` — delete-only + comment scrub; absence proven by post-green
grep under `apps/menubar` (zero shadow-trio hits) and remaining suite green
without the three dedicated harness test files.

Why this path: deleted the three Phase-18-retained shadow utilities and their
orphaned-only tests, regenerated `Codogotchi.xcodeproj` via xcodegen, and
rewrote five present-tense lies (`DesiredWindows.titleResolutionRequests`,
`PoolMemory.promptTimers`, `PoolDerive` observe-before-guards note,
`FloatingPetPanelController` / `MinimalistBadgeView` presentation docs) to
match the live derive → apply presentation push. `Menubar.xcodeproj` was
already absent on `v3_preview` — nothing to delete for the husk.

Alternative considered: keeping the recording proxy as a general test double —
rejected; ticket commits delete-not-relocate, and no production or remaining
test path required it after Phase 18 closeout.

Deferred: fold-display / prune-title (P21.02); presentation-only protocol
surface (P21.03); allocator/Pruner unify (P21.04). Historical delivery docs /
retrospectives that name the trio stay as archaeology.

Contract note: behavior freeze held — no pool update, prune, or timer path
change beyond comment text and deleted unused utilities.
