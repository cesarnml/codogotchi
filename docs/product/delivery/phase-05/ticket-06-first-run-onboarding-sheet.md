# P5.06 First-run onboarding sheet

Size: 3 points
Type: feat
Scope: onboarding
Red: required

## Outcome

- Menubar-attached sheet (or equivalent modal) on first launch when `onboarding_completed_at` is absent.
- Copy explains: animation driven by agent hooks; Codex + Claude installable in this phase; Cursor/VS Code/Antigravity detected and labeled **deferred** or **bridge-only** per product plan.
- Single primary action: **Approve & install hooks** — runs `codogotchi hooks install` subprocess; shows stderr on failure.
- **No** skip, "Not now", or dismiss-without-install that marks onboarding complete.
- On success, set `onboarding_completed_at`; until hook activity observed, show persistent **Hooks not active** with next action (retry install / open Settings).
- Pet remains **idle** (no user demo); mouse interactions on floating pet unchanged.
- Sheet does not block app launch indefinitely on subprocess failure — CTA remains until healthy.

## Red

- Write failing tests where possible: onboarding flag gating; subprocess invoked on approve (inject mock); completion requires install success path.
- UI tests optional if harness heavy — minimum: unit tests for onboarding state machine.
- Commit: `test(P5.06): onboarding consent and install flow [red]`.

## Green

- Build SwiftUI/AppKit sheet UI wired to P5.05 bootstrap and hook client.
- Wire honest platform labels from status JSON or disk probe.

## Refactor

- Do not duplicate hook merge logic in Swift.

## Review Focus

- Tone matches product: hooks are required for a real install, not optional frosting.
- Failed install is visible and recoverable.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
