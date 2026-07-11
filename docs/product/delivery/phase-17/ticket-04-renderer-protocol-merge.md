# P17.04 Renderer protocol merge

Size: 3 points
Type: refactor
Scope: menubar
Red: skip

## Outcome

- `FloatingPetPanelManaging` and `MinimalistPanelManaging` no longer exist as separate protocols; one renderer protocol ("one renderer interface, two skins") is declared once, with `FloatingPetPanelController` and `MinimalistPanelController` as its two conformers.
- Per-shape differences the old protocols encoded structurally (e.g. `applyBadgeScale` on Minimalist only) are expressed as capabilities consistent with `docs/contracts/window-capability-matrix.md`, not as a second protocol.
- `FloatingPetController` and all other consumers hold the merged protocol type; no call site downcasts to a concrete panel controller to reach a method the merge dropped.
- Existing tests pass unmodified — the neutrality proof; zero behavior change.
- `MenubarApp` is touched only where type names force it — factory structure and wiring are untouched (that is P17.05's disruption).

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- This ticket introduces no new behavior: it unifies protocol declarations while conformer bodies stay unchanged. The neutrality proof is the existing suite passing unmodified; a new test asserting protocol shape would be implementation-first.

## Green

- Declare the merged renderer protocol; migrate both conformers and every consumer; delete both old protocol declarations in the same PR.
- Where the two protocols' members diverge, resolve per the matrix: shared members unify; shape-specific members become capability-conditional surface, defaulted or no-op'd exactly as current behavior dictates (mirroring the existing `applySessionLabel` no-op documentation pattern).

## Refactor

- This ticket *is* the refactor; keep it mechanical. Conformer method bodies must be diff-identical except signatures the merge forces.
- Only refactor what you touched — no drive-by cleanup inside panel controllers.

## Review Focus

- The merge direction: verify no Minimalist-only or Own-only member silently gained behavior on the other shape (a no-op that becomes an op is a behavior change).
- Diff discipline: conformer bodies unchanged; the PR should read as declarations moving, not logic changing.
- No compatibility shims or dual conformances left behind — the Phase 16 `WindowKey` no-shims precedent applies.
- Consumers: check `FloatingPetController` and pool call sites hold the merged type; no `as?` escapes.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a — `Red: skip`; neutrality proven by the unmodified existing suite.
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: factory collapse and router wiring (P17.05); any protocol-surface redesign beyond the merge.
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
