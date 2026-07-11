# P16.02 Split FloatingPetPanel.swift

Size: 3 points
Type: refactor
Scope: menubar
Red: skip

## Outcome

- `apps/menubar/Sources/Windows/FloatingPetPanel.swift` (5,144 lines, ~30 top-level types) no longer exists.
- Every type it contained lives in its own file under `Windows/`, named after the type (type-per-file).
- No signature changes, with one sanctioned deviation: `private` (file-scoped) types widened to `internal` where extraction forces it — and no new call sites appear for any widened type.
- Full existing suite green, unmodified.

## Extraction map (clusters → files, all under `Windows/`)

- Minimalist panel: `MinimalistPanelController`, `MinimalistBadgeView`, `MinimalistPanelSizePill` (+ `FirstMouseSlider`, `MinimalistPanelSizePillPanel`).
- Main panel: `FloatingPetPanelController`, `FloatingPetInteractionView`, `FloatingPetOverlayView`.
- Gate badge system: `GateBadgeLayout`, `GateBadgePanel`, `GateBadgeView`, `GateBadgeTokenView`.
- Animation badge system: `AnimationBadgeLayout`, `AnimationBadgePanel`, `AnimationBadgeChrome`, `AnimationBadgeView`, `PlatformChipView`, `PromptTimerChipView`, `TimerIconChipView`, `AnimationLabelPillView`, `PlatformSessionBadge`.
- Prompt system: `FloatingPetHidePrompt` (+ its extension — merge into the type's file), `FloatingPetPromptItem`, `FloatingPetPromptCoordinator`, `FloatingPetHidePromptPanel`, `FloatingPetHidePromptView`, `FloatingPetHidePromptTintView`.
- Interaction policy: `FloatingInteractionHitTarget`, `FloatingInteractionPolicy`.

Tiny leaf types (e.g. a token view under ~100 lines) may share a file with their sole owner if extraction to a standalone file adds nothing — note each such case in Rationale. ~1,500 lines per file is guidance, not a gate.

## Red

- `Red: skip` — mechanical extraction; no behavior is added or changed. The existing suite passing unmodified is the gate.

## Green

- Extract each type into its own file under `Windows/`; delete `FloatingPetPanel.swift` in the same commit series.
- Widen `private` → `internal` only where the compiler forces it; keep `fileprivate`/`private` where types co-locate.
- Preserve doc comments and `// MARK:` structure with their types.
- Build and run the full suite after extraction.

## Refactor

- None beyond the extraction itself. No renames, no signature changes, no opportunistic cleanup.

## Review Focus

- **Verbatim invariant:** every line removed from `FloatingPetPanel.swift` reappears in exactly one new file, modulo access keywords and file headers. Verify with a moved-code diff, not eyeballs.
- **Access-widening audit:** for each `private` → `internal` change, confirm no new call sites were introduced.
- File-per-type conformance and correct drawer (`Windows/`).
- No behavioral drift smuggled in as "cleanup."

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (`Red: skip` — extraction only)
Why this path: single PR deleting the file gives an atomic "file no longer exists" exit check
Alternative considered: three cluster-sized PRs — rejected; clusters cross-reference and intermediate half-alive states add ambiguity
Deferred: any prompt/dismissal convergence (Phase 17); renames
