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

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
