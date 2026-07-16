# P21.02 Collapse prune title; remove foldedSessionDisplay E2E

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- Prune menu item and confirmation-alert titles use the bare `FloatingPetHidePrompt.pruneTitle` (or equivalent constant) — no discarded `foldedSessionDisplay` parameter on `pruneMenuTitle`.
- End-to-end audit of `foldedSessionDisplay` (DesiredWindow → derive → PoolApply → protocols → Own/Minimalist views → prompt builder/alerts) is recorded in Rationale.
- If the audit confirms prune UI was the sole consumer (expected after P19.04): the field and `applyFoldedSessionDisplay` push path are removed from DesiredWindow, PoolApply, window/panel protocols (and defaults), and both skins’ views/controllers; derive no longer computes it.
- If a real non-prune consumer is found: **stop** per phase stop conditions — do not land a half-dead field; re-grill before expanding.
- Behavior freeze: prune still available with the same affordance gating; only the title string path simplifies (identity already on mode-indicator / session chip).

## Red

- Add/adjust tests that fail until prune title is exactly `pruneTitle` with no fold-display interpolation / discarded parameter API.
- Add/adjust tests that fail until the dead fold-display push/threading is gone (e.g. prompt-builder / hide-prompt / apply push assertions), consistent with full E2E removal once audit confirms prune-only.
- Run suite; confirm red fails; commit with suffix `[red]` before green.

## Green

- Collapse `pruneMenuTitle` call sites to `pruneTitle` (delete the no-op wrapper if unused).
- Remove fold-display field/push/storage end-to-end when audit confirms prune-only.
- Smallest change — no timer-protocol or allocator work.

## Refactor

- Only touch fold-display / prune-title surfaces required for the outcome. No opportunistic protocol merges.

## Review Focus

- Audit conclusion must be explicit in Rationale (prune-only → deleted; otherwise stopped).
- Do not leave `applyFoldedSessionDisplay` on protocols with derive still setting the field “for later.”
- Prompt builder / interaction / minimalist alert titles all use bare prune title.
- No user-visible change beyond removing dead title expansion that already returned a constant.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Mirror absence tests on `DesiredWindow` / `FloatingPetPromptCapabilities`
plus a PoolApply update path that must not thread fold-display. All three failed
against the pre-green surface, then passed after E2E removal.

Why this path: Audit of DesiredWindow → derive → PoolApply → protocols →
Own/Minimalist views → prompt builder / prune alerts confirmed **prune-only**
consumers (every live read fed `pruneMenuTitle` / prune alert copy). Deleted
the field, compute, push, protocol members, view storage, and the no-op
`pruneMenuTitle` wrapper; call sites use bare `pruneTitle`.

Alternative considered: keep the field for a hypothetical future non-prune
consumer — rejected; phase stop conditions require full delete once audit is
prune-only, not a half-dead push.

Deferred: timer-protocol surface (P21.03); allocator/Pruner unify (P21.04).

Contract note: behavior freeze — prune affordance gating unchanged; only the
dead title-expansion parameter path is gone (already returned a constant since
P19.04).
