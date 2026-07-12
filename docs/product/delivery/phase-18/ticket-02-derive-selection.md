# P18.02 Derive selection — cap/eviction, grandfather, frame directives, user-action transitions

Size: 3 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `derive` covers the pool's admission and teardown policy as pure logic: combined-mode collapse of directly-keyed windows (Step 6a), session-shape mismatch / grandfather collapse with enabling-direction frame capture (Step 6a2), own↔minimalist spawned-mode mismatch teardown (Step 6b), and per-origin session-cap selection via `SessionSelectionPolicy` (Step 6c) including slot occupancy resync, pinned hidden keys, pruned-origin promotion restriction, genuine-eviction hidden-flag purge, and blocked-origin computation.
- Frame-inheritance directives are data: the evicted/grandfathered frame FIFO lives in `PoolMemory` (capture points as directives; the queue drains on spawn in `DesiredWindows` order), and no CGRect values are fabricated — capture directives reference the torn-down window key; `apply` reads the actual frame at execution time.
- Session numbering is pure: the free-list allocator is a value type in `PoolMemory`; assign-on-spawn/release-on-teardown semantics (including the unlimited-cap sentinel and release-from-captured-identity rule) match today's `SessionNumberAllocator` + `windowSessionIdentities` behavior.
- Out-of-band user actions exist as pure transition functions on `PoolMemory` — `hiding(_:)`, `showing(_:)` (with the lastSeen re-seed rule), `pruning(_:)` (origin arming + bookkeeping clears), `hidingAllOthers(keeping:)`, `resettingPromptTimer(for:)` — unwired, matching the semantics of `setVisible`, `pruneSession`, `hideAllOtherWindows`, and `resetPromptTimer`.
- Named table-driven tests exist for the Phase 15 QC gap classes owned here: **mode-transition teardown**, **hide vs. cap incumbency** (hidden incumbent keeps slot; genuinely evicted hidden key loses its flag), **grandfather admission** (both toggle directions), **eviction frame-inheritance** (multi-eviction FIFO across ticks).
- Still unwired; live pipeline untouched; full existing suite green; purity gate green.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Write the four gap-class tables first as failing tests — each row named after the behavior it locks (e.g. `hiddenIncumbentKeepsSlotUnderCapPressure`), with multi-tick folds where the bug class is a transition (eviction FIFO, prune arming, show-after-TTL re-seed).
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.02): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Transcribe Steps 6a–6c and the user-action semantics from `FloatingPetWindowPool` — including every inline P15.07/P15.07-QC/P15.08 invariant comment — into derive and the transition functions.
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Adversarial cross-check against Phase 15 QC history: each QC fix in the old pipeline (slot kept while hidden, frame FIFO not overwritten, prune arming never cleared, hidden-flag purge on genuine eviction) must be identifiable as a specific table row AND a specific derive branch.
- Frame directives: verify the FIFO ordering guarantee survives `DesiredWindows` being a dictionary — spawn-order determinism must be explicit (sorted, as Step 6's comment requires), not incidental.
- Allocator value-type conversion: release must use assign-time identity, not the latest snapshot (the leak-under-cap bug); confirm a test locks this.
- User-action transitions: `showing` must re-seed the TTL clock (the Show-is-a-silent-no-op bug); confirm the two-limb contract (pure transition + immediate effect) is documented on each function for P18.06 wiring.
- Intentionally deferred: combined folding and all push payloads (P18.03); any effect execution (P18.04+).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: the pre-existing `PoolDeriveSelectionTests.swift` (commit `b87f09da`) failed to compile — it referenced `PoolMemory`/`PoolDerive`/`DesiredWindow` API surface that did not exist yet (`slotOccupants`, `prunedOrigins`, `userHiddenWindowKeys`, `windowSpawnedModes`, `evictedFrameDirectives`, the five user-action transitions, `inheritedFrameFrom`). Before implementing, a second focused red test was added (`PoolMemorySessionAllocatorTests.swift`, decision 2 below) locking the session-number allocator's release-from-captured-identity contract; confirmed red via a second compile failure (`sessionNumberAllocator`/`windowSessionIdentities` absent), then committed separately as `test(P18.02): lock session-number allocator release-from-captured-identity [red]`.

Why this path: the smallest-acceptable-and-correct implementation turned out to be a genuine architectural simplification rather than a literal step-by-step transcription of `FloatingPetWindowPool`'s imperative Steps 5a/6a/6a2/6b. Those steps exist ONLY because the legacy pipeline keeps a `windows` dictionary that persists stale entries across ticks — an origin switching mode, session-pets shape, or session-cap membership requires an explicit "notice the mismatch, tear the stale entry down" branch for each of the four ways staleness can happen. `PoolDerive.derive` recomputes desired membership from scratch every tick from a single fold function (`desiredWindowKey(_:)`, combining Step 6/6a/6a2's fold rules: combined-mode always folds to `.combined`; a non-combined origin with session-pets off folds every render key sharing that origin down to the plain `.origin(origin)` key; otherwise the render key's own shape is preserved). Because there is no stale `windows` dict to mismatch against, Steps 5a/6a/6a2/6b's imperative teardown-detection collapses to nothing — the four named "mode-transition teardown" test rows pass with no code dedicated to detecting a transition at all. The one thing this pure-fold model needs that the imperative pipeline got for free from `windows` persisting across ticks is `PoolMemory.previousDesiredWindowKeys` — the prior tick's actual (non-hidden) desired membership, diffed against this tick's freshly-computed membership to detect (a) a grandfather-frame capture opportunity (Step 6a2 enabling direction: a plain window desired last tick, gone this tick, now that session-pets is on) and (b) which keys are freshly spawning (eligible to drain a queued frame directive and assign/release a session number). This is a deliberate, documented deviation from literally transcribing the six imperative teardown/spawn steps — the fold model is smaller, cannot regress into any of the four bug classes by construction, and every RED-step test still passes as a specific, named branch.

Alternative considered: literally porting Steps 5a/6a/6a2/6b as separate imperative branches operating on an explicit `Set<WindowKey>` standing in for `windows.keys`, mirroring `FloatingPetWindowPool` method-for-method. Rejected: it would have reintroduced the exact "four different places a stale entry can leak through" surface area the pure-fold model eliminates, for no behavioral benefit — the phase's whole bet (per the implementation plan's Grill-Me decision 1) is that a Moore-machine fold makes these bug classes structurally unrepresentable rather than separately patched, and a literal transcription would have thrown that away while producing a larger, harder-to-review diff.

Deferred (unchanged from the ticket's Review Focus): combined folding's full richness (winner election across several combined-mode origins, the style-toggle collapse, the shared prompt timer) and every push payload (`activityState`, `attention`, `gateBadge`, `platformChip`, `sessionNumber`/`sessionLabel`/`sessionTooltip`, `promptTimerStatus`, `conflictBubble`, `hudEnabled`) remain P18.03. `derive` only guarantees `DesiredWindow.isMinimalist` and `.inheritedFrameFrom` are correct this ticket; TTL-expiry and hidden-key gating for the trivial already-`.combined`-keyed case are implemented at render-key granularity rather than the full per-window-key `lastSeenForWindow` max-across-folded-keys legacy uses for combined — safe given only the trivial single-entry combined test exists this ticket, and explicitly a P18.03 follow-up once combined folding's full richness lands. Conflict-bubble presentation/rate-limiting and resolved session titles also remain deferred (P18.03/P18.04).

Contract note: `DesiredWindow.inheritedFrame: CGRect?` (P18.01's placeholder) is replaced by `inheritedFrameFrom: WindowKey?`, per this ticket's explicit Outcome bullet 2 ("no CGRect values are fabricated ... capture directives reference the torn-down window key; `apply` reads the actual frame at execution time"). This revises a prior ticket's placeholder field shape, not a mistake in that ticket — flagged here per the ticket owner's decision recorded in the delivery brief.

Behavior-freeze concern flagged for developer review (not silently resolved either direction, per the phase's binding divergence policy): `FloatingPetWindowPool.slotOccupants`'s own doc comment states the per-origin cap-selection step "replaces that origin's **slice** of this set every tick" — but the literal code (`slotOccupants.subtract(keys); slotOccupants.formUnion(selection.rendered)`, where `keys` is only THIS TICK'S visible session-keyed render keys for the origin) does not actually do that: a session key that disappears from the snapshot entirely (TTL/prune/anything else) before its cap-selection loop iteration ever sees it again is never subtracted, so it appears to remain a phantom slot occupant for that origin indefinitely (until eligibility-bounding removes it from `lastSeenAt` et al., which does not touch `slotOccupants` either). The P18.02 RED test `test_slotOccupancyResyncsToExactlySelectionRenderedEveryTick` requires (and this implementation provides) a full per-origin-slice replacement — subtracting every existing `slotOccupants` entry for the origin, not just the ones visible this tick — matching the field's documented contract rather than the literal legacy loop. I have NOT modified `FloatingPetWindowPool` itself (out of scope / untouched per this ticket's mandate), so this is a live, unresolved divergence between the old and new pipelines that will surface at shadow-compare (P18.05): please confirm whether the legacy behavior is an actual latent slot-leak bug (in which case it should be fixed in the old pipeline first, per the divergence policy, with its own ledger entry) or whether there is a reason the narrower literal behavior is intentional that I'm not seeing.
