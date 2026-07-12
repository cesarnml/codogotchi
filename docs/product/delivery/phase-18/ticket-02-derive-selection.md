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

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
