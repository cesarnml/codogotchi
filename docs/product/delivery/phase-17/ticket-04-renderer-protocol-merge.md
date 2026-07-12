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

Red first: n/a — `Red: skip`; neutrality proven by the unmodified existing suite (`bun run mac:test`, 1065 tests, 0 failures, all assertions unmodified except the two test-double conformance clauses).
Why this path: merged `FloatingPetPanelManaging` and `MinimalistPanelManaging` into a single `PanelManaging` protocol declared once in `FloatingPetController.swift`, with one default-impl extension holding every shape-specific member as a no-op (Floating-only: `apply(state:visualMode:)`, `replacePets`, `applyRPGState`, `setRPGHUDEnabled`, `setHUDDemoActive`, `setHUDPinned`, `setInteraction`, `updateIdleEscalationConfig`; Minimalist-only: `applyActivity`, `applyPromptSummary`, `applyBadgeScale`). This is the smallest change that satisfies "one renderer interface, two skins" from `docs/contracts/window-capability-matrix.md` §2 without forcing either conformer to implement members outside its shape.
Alternative considered: keeping two protocols with a shared base protocol for the common members (`show`, `hide`, `applyPlatform`, etc.) and two thin shape-specific extensions. Rejected — that's still two protocol types at the consumer/storage boundary (`FloatingPetController.panel` and `MinimalistWindowController.panel` would still differ), which doesn't satisfy the ticket's "one renderer protocol" outcome; the merge with per-shape no-op defaults gets to a single storage/consumer type instead.
Deferred: factory collapse and router wiring (P17.05); any protocol-surface redesign beyond the merge.
Contract note: none — `Type: refactor`, `Scope: menubar`, `Red: skip` all matched the actual work; no deviation.
