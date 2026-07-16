# P21.03 Presentation-only prompt-timer protocols; private heartbeat helper

Size: 3 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- Production protocols used by `PoolApply` (`FloatingPetWindowControlling`, and the matching `PanelManaging` surface) expose **presentation** push only — `applyPromptTimerStatus` is not part of those public protocols (or their default no-op extensions).
- `PoolApply.push` continues to call presentation only (already true); stubs/tests conforming to the window protocol no longer need a status method.
- Own panel + Minimalist badge retain a **file-private or internal** helper (e.g. heartbeat / override-clear) that preserves today’s local timer cadence and the clear-override behavior previously driven via status. Controllers do not re-advertise status on the pool-facing protocol.
- `MinimalistBadgeViewTests` (or successor) still prove that clearing via the helper does not leave a stale presentation override shadowed incorrectly.
- On-screen timer labels: no intentional change to elapsed display, wipe/reset, or chip visibility (behavior freeze).

## Red

- Tests fail until production protocol / stub surface is presentation-only (status no longer required on `FloatingPetWindowControlling` conformers used by PoolApply tests).
- Override-clear regression fails until rewritten against the private/internal helper (or equivalent surviving API) — do not delete the regression.
- Run suite; confirm red fails; commit with suffix `[red]` before green.

## Green

- Remove status from window/panel production protocols and forwards; add private/internal helper on Own/Minimalist implementations; retarget tests.
- Scrub any remaining false “still unwired (P18.05)” comments on the presentation path if P21.01 missed a site adjacent to this edit.
- Smallest change — do not delete local `Timer` / switch to derive-only sub-second ticking this ticket. Do not touch allocator/Pruner.

## Refactor

- Rename/relocate helper as needed for `@testable` access; no Own/Minimalist persist extraction (deferred).

## Review Focus

- Dual public push is gone; freeze bar on timer feel holds.
- Override-clear regression must survive, not be waived.
- Do not expand into `visualMode` / desaturated wiring or Visibility protocol merge.
- Stop if timer feel cannot be preserved without a product-visible change — do not invent derive-only tick “fixes.”

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `PromptTimerProtocolSurfaceTests` failed while
`FloatingPetController.swift` still declared `applyPromptTimerStatus` on
pool-facing protocols.

Why this path: Removed status from `FloatingPetWindowControlling` /
`PanelManaging` (and window-controller forwards). Kept Own/Minimalist local
heartbeat + override-clear as `applyLocalPromptTimerStatus` (internal,
`@testable`-reachable). Retargeted
`testRawStatusPushTakesOverFromAPriorPresentationOverride`. Live tick remains
presentation-only via `PoolApply` (already true). Local `Timer` heartbeat left
intact — no derive-only sub-second change.

Alternative considered: deleting local heartbeat entirely and relying only on
derive ticks — rejected; ticket freeze / stop condition forbids inventing
derive-only cadence “fixes” this phase.

Deferred: Own/Minimalist shared persist/timer extraction; Visibility protocol
merge; allocator/Pruner (P21.04).

Contract note: behavior freeze on elapsed display / wipe / chip visibility —
protocol surface narrows only.
