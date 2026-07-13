# P18.04 Diff, apply, recording proxy, and comparator

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `diff(desired:current:)` is a mechanical set comparison: spawn / dismiss / update sets keyed by `WindowKey`, with frame-inheritance directives passed through as data — no policy branches (any needed decision is evidence of a P18.03 gap, fixed there).
- `apply` executes a diff against the Phase 17 converged factories: spawn (with directive-driven frame adoption read from the live donor window at execution time), teardown, and per-window pushes straight from `DesiredWindow` fields; performs title resolution for `titleResolutionRequests` (disk cache read-through + write-through) and feeds results back for the next tick's memory. Zero policy decisions.
- A recording `FloatingPetWindowControlling` proxy exists: forwards every call to a wrapped controller while logging pushes per tick; also runnable against a stub (no real window) whose `currentFrame` reads through to a live window by key — both shadow directions covered.
- A field-level comparator diffs recorded old-pipeline behavior + extracted decision sets against a `(DesiredWindows, PoolMemory)` pair: asserts under tests/debug, emits structured divergence records (tick-input fingerprint, field path, both values) for log-only use. Frame directives compared structurally, never CGRect values. The title-seam delay is a built-in exemption.
- Still unwired into the live tick; full existing suite green; purity gate green (diff is pure and lives in `Pool/Derive/`; apply/proxy/comparator live outside it and may import AppKit).

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Failing tests first: diff set algebra (spawn/dismiss/update partitioning, directive pass-through), apply against mock controllers (push completeness — every `DesiredWindow` field reaches the controller), proxy forwarding fidelity, comparator detection of a seeded single-field divergence and honoring of the title-seam exemption.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.04): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement the smallest change that makes the failing test pass
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Hunt for policy hiding in `apply` — any `if` on domain state (mode, activity, cap, TTL) rather than on diff/spec data is a violation of the phase's fixed constraint.
- Push completeness: a `DesiredWindow` field that apply never forwards is a silent behavior change the comparator can't see from the new side — check field-by-field.
- Comparator exemption mechanism: exemptions must be named and enumerated (currently exactly one), not pattern-matched loosely.
- Proxy: verify the stub direction's `currentFrame` read-through — post-cutover reversed shadowing depends on it (P18.06).
- Intentionally deferred: any wiring into the live tick (P18.05).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `PoolDiffTests`, `PoolApplyTests`, `RecordingFloatingPetWindowControllingProxyTests`, and `PoolShadowComparatorTests` all failed to compile (`cannot find 'PoolDiff'/'PoolApply'/'RecordingFloatingPetWindowControllingProxy'/'PoolShadowComparator'/'ShadowCompareExemption' in scope`) against commit `ffd27cee`, confirming none of P18.04's four new types existed yet.

Why this path: each of the four pieces is the smallest mechanical translation the ticket's Outcome describes, with no new abstraction beyond what a test required. `PoolDiff.diff` is pure key-membership set algebra (`Pool/Derive/PoolDiff.swift`, no AppKit — purity gate green). `PoolApply.apply` (`Pool/PoolApply.swift`) reads every spawn's frame-inheritance donor's `currentFrame` into a side table *before* running the dismiss loop, so a donor evicted the same tick it hands off its frame is read before teardown removes it — the only ordering constraint the ticket's concurrent spawn+teardown test enforces. `RecordingFloatingPetWindowControllingProxy` (`Pool/RecordingFloatingPetWindowControllingProxy.swift`) forwards every protocol call 1:1 to a wrapped controller, records a `RecordedPush` per push-payload call in order, and resolves `currentFrame` via an optional `liveFrameLookup(key)` that wins over the wrapped controller's own frame only when it resolves non-nil — covering both shadow directions with the same type. `PoolShadowComparator.compare` (`Pool/PoolShadowComparator.swift`) walks every shared `DesiredWindow` field pairwise and reuses `DesiredWindows.titleResolutionRequests` (mapped `RenderKeyIdentity` → `WindowKey.session`) as the sole, narrowly-scoped `sessionLabel` exemption gate.

Alternative considered: modeling `apply`'s title resolution as part of the required 3-argument `apply(diff:controllers:spawn:)` signature the tests exercise, so the same call that pushes fields also resolves titles. Rejected: none of `PoolApplyTests`' cases exercise title resolution (explicitly out of scope per that file's own doc comment), and folding it into `apply` would force a signature the red tests don't require while also making `WindowDiff` (which carries no `titleResolutionRequests`) respondible for pool-level data it doesn't own. Instead `PoolApply.resolveTitles(requests:readCachedTitle:resolveTitle:writeCachedTitle:)` is a separate, independently-testable function with injectable dependencies mirroring `FloatingPetWindowPool.resolveSessionTitle`'s existing cache-then-resolve-then-write-through shape (`RetrievedSessionTitleStore` disk cache checked first, `SessionTitleResolver` on miss, write-through on a fresh resolve) — a future ticket wires its `[RenderKeyIdentity: String]` result into `PoolMemory`.

Deferred: wiring `derive → diff → apply` into `FloatingPetWindowPool`'s live tick (P18.05, per the ticket's explicit deferral); folding `resolveTitles`'s output back into `PoolMemory.resolvedSessionTitles` (no live caller exists yet, so there is nothing to fold into); `PoolShadowComparator`'s decision-set half (membership, spawned modes, blocked/pending/TTL-dismissed sets, session numbers, hidden keys) — `PoolShadowComparatorTests`' own scope note representing "old" as a `[WindowKey: DesiredWindow]` (this ticket's per-window push-payload half only) rather than inventing a comparable shape for the old pipeline's equivalent of `PoolMemory`, which the ticket does not spell out; `apply` never calls `replacePets(codexPet:codogotchiPet:)` since resolving `DesiredWindow.petId` into concrete `CodexPet`/`CodogotchiPet` assets needs a pet-catalog lookup outside `DesiredWindow`'s own data — untested by `PoolApplyTests` and left for a follow-up.

Contract note: `DesiredWindow.promptTimerStatus` is a `PromptTimerPresentation` (P18.03's already-rendered label/isRunning pair) while `FloatingPetWindowControlling.applyPromptTimerStatus` took the raw pre-render `PromptTimerStatus`. Per this ticket's pre-stated architectural decision, added a new protocol requirement `applyPromptTimerPresentation(_ presentation: PromptTimerPresentation?)` (default no-op in the `FloatingPetWindowControlling` extension) rather than reconstructing a fake raw `PromptTimerStatus` in `apply`, which would fabricate a `startedAt` never actually observed. Implemented on every real conformer: `FloatingPetController`/`MinimalistWindowController` forward to a matching new `PanelManaging.applyPromptTimerPresentation` member (also default-no-op'd), which `FloatingPetPanelController` and `MinimalistPanelController`/`MinimalistBadgeView` implement by forwarding the given presentation directly to their existing renderer calls (`chromeCoordinator.repositionAnimationBadge(promptTimer:)`, `animationBadge.configurePromptTimer(_:)`) rather than re-deriving one via `.presentation()` on anything. This new path deliberately does not participate in either panel's local heartbeat `Timer` (`syncPromptTimerHeartbeat`): those tick the *raw*-status path (`applyPromptTimerStatus`) the still-live old pipeline drives today; once `apply` is wired into the live tick (P18.05), per-tick redraws will come from `PoolDerive` recomputing a fresh `PromptTimerPresentation` every tick rather than a local timer, so no parity gap survives cutover — flagging this explicitly for reviewer attention since it's a plausible-looking gap in isolation. Test-double conformers (`MockController`, `InertController`, `StubWindow`, `StubWindowController`) needed no changes: the new member's protocol-extension default keeps them compiling unmodified, exactly as the ticket's Scope note anticipated. Separately (not a contract deviation, but worth flagging for review): `RenderKeyIdentity` gained a `Hashable` conformance (was `Equatable`-only) so `PoolApply.resolveTitles` could key a `[RenderKeyIdentity: String]` dictionary by it — a minimal, additive, non-breaking change to an existing P15 type.
