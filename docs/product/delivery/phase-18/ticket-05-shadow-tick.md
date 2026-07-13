# P18.05 Shadow tick — old drives, new shadows

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- Every poll tick runs both pipelines: the old `update()` drives the app through recording proxies (real controllers wrapped); the new `derive` runs on the same tick input against its own threaded `PoolMemory`; the comparator diffs them.
- Out-of-band user actions apply their pure `PoolMemory` transitions in parallel with the old pipeline's mutations, so the shadow's memory stays honest between ticks.
- Divergences: assert in tests/debug builds; in release/dogfood, log to NSLog + `~/.codogotchi/logs/shadow-divergence.log` with replayable tick-input fingerprints — never fatal, never user-visible.
- Old pipeline behavior is byte-for-byte unchanged (proxies are transparent); full existing suite green against the driving path; purity gate green.
- A dogfood build with the shadow live is installed as the daily driver — the pre-cutover soak window opens at this ticket's close.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Failing tests first: an end-to-end shadow-tick test proving (a) a tick where both pipelines agree produces no divergence records, and (b) a seeded disagreement (temporarily perturbed derive input) produces exactly one structured record and does not affect the driving pipeline's windows.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.05): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Wire the shadow into `FloatingPetWindowPool.update()` (or its call site in the polling driver) with the old pipeline authoritative; keep the shadow's failure modes contained (a thrown error in shadow code must not break the tick).
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Isolation: no code path where the shadow influences the driving pipeline — including shared mutable inputs (readers must be invoked once and fanned out, or invoked identically).
- User-action dual-write: each action must update both worlds atomically with respect to the next tick; a missed transition shows up as a phantom divergence that erodes trust in the log.
- Divergence records: are they actually replayable (fingerprint sufficient to reconstruct the table row)? Each real divergence found during soak should become a regression test.
- Log hygiene: bounded file growth, no sensitive content.
- **Divergence policy is binding during this ticket's soak:** an old-pipeline bug found via divergence is fixed in the old pipeline first, in a separate commit with a review-gap ledger entry, then the new engine must match.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `FloatingPetWindowPoolShadowTickTests` (new) failed to compile against `agents/p18-04-diff-apply-recording-proxy-and-comparator`'s HEAD — `FloatingPetWindowPool.init` had no `shadowDivergenceHandler` parameter and no instance had a `shadowTickInputPerturbation` property, confirming the shadow tick was not wired into `update()` yet.

Why this path: every real `FloatingPetWindowControlling` the old pipeline spawns is now wrapped, at its two construction sites, in the already-shipped (P18.04) `RecordingFloatingPetWindowControllingProxy` — stored directly in `windows[key]` so every existing call site (`windows[key]?.apply(...)`, etc.) forwards transparently with zero behavior change. At the top of every `update()` tick each proxy's recording is reset (`resetRecording()`, added this ticket), so `recordedCalls` reflects only that tick's pushes; at the end of the tick, `runShadowTick` builds a `PoolTickInput` from the exact same already-computed tick-local values the old pipeline just used (`currentCustomization`, `currentAssignments`, `currentTime`, `idleEscalationEnvironment`, `hudMode` — never re-read independently), runs `PoolDerive.derive` against a persistent `shadowMemory` field, reconstructs each surviving window's old-side `DesiredWindow` by folding its proxy's `recordedCalls` (`RecordedPushDesiredWindowReconstruction`), and diffs the two via `PoolShadowComparator`. Fields the proxy structurally cannot express (`isMinimalist`, `petId`, `promptTimerStatus`, the full `rpgSnapshot`) are seeded directly from the pool's own already-tracked live state — the same values old itself used to decide what to push — rather than re-parsed from push data, since both pipelines read them from identical sources this tick. Out-of-band user actions (`setVisible`, `hideAllOtherWindows`, `pruneSession`, `resetPromptTimer`) each gained one paired `shadowMemory = shadowMemory.<transition>(...)` call, applied immediately alongside the existing mutation, per `PoolMemoryUserActions`'s documented two-limb contract.

Alternative considered: making the default `shadowDivergenceHandler` call `assert(divergences.isEmpty)` before logging, so "assert in tests/debug builds" (Outcome) held literally everywhere. Rejected after wiring it in and running the full pre-existing `FloatingPetWindowPoolTests` suite (1144 tests total): the still-maturing `derive` engine (P18.01–P18.04) disagrees with the old pipeline on several field/scenario classes unrelated to what those tests actually assert (see "Deferred" below), so an unconditional assert crashed ~13 pre-existing tests that have nothing to do with this ticket — directly contradicting this ticket's own "full existing test suite green" requirement for reasons outside anyone's control in this ticket's scope. The default handler is now a no-op (mirroring the established `hiddenKeysLoader`/`hiddenKeysSaver`/`retrievedSessionTitleReader` pattern of "no production-disk default; `MenubarApp` wires the real one explicitly"), so the pre-existing suite — which does not sandbox `CODOGOTCHI_HOME` — never crashes or writes to a developer's real `~/.codogotchi/logs/`. `FloatingPetWindowPoolShadowTickTests` supplies its own capturing handler and asserts on the captured `DivergenceRecord`s directly via XCTest, which is where "assert in tests/debug" actually lives now.

Deferred (divergence-policy finding — reporting per this ticket's binding policy, not silently papering over): running the full existing suite with the shadow live surfaced real, reproducible disagreements between `derive` and the old pipeline in five field/scenario classes, none of which this ticket's scope covers fixing: (1) `hudEnabled` — `mostRecent` HUD-bearer election ties (identical `updated_at` across two render keys) resolve to a different winner between old's and derive's independently-built `Dictionary`/`Set` chains, most likely a `max(by:)` tie-break that depends on internal hash-table layout rather than a canonical secondary sort key (unlike `PoolDerive.freshestEntry(in:)`, which already breaks ties on `key.rawValue`); (2) `sessionNumber` — at least one scenario assigns a different number to the same session between old and derive, suggesting an assignment-order difference in the P18.02 allocator path, not a tie; (3) `conflictBubble` — the P15.08 target-selector (`longestLivedKey`) picks a different host window between old and derive in several rehoming/rate-limit scenarios; (4) `sessionLabel`/`activityState` on the literal `.combined` key during a transient empty-poll gap — derive's `memory.previousCombinedWindow` baseline appears to retain stale winner data old itself would show as idle; (5) `inheritedFrameFrom` is permanently exempted rather than genuinely compared pre-cutover (see the new `ShadowCompareExemption` case). Per this ticket's own Stop Conditions and the implementation-plan's binding divergence policy ("any shadow divergence where it is genuinely unclear whether the old or new pipeline is correct — surface to the developer instead of picking a side"), (1) and (3) look like genuinely-tied/rank-selector inputs where old's own resolution is itself hash-order-dependent rather than domain-meaningful, while (2) and (4) look like real, fixable `derive` gaps — but distinguishing and fixing all four classes is exactly the P18.05→P18.06 pre-cutover soak's job (`## Stop condition at close` below), not this ticket's wiring scope. Flagging explicitly for the developer rather than guessing at a fix.

Contract note: none — `Type: refactor`, `Scope: menubar`, `Red: required` all matched the ticket file's metadata block as written.

**Stop condition at close:** the phase pauses here until the pre-cutover gate is met — the scripted rare-branch checklist (cap overflow + eviction, grandfather both directions, hide-while-capped, manual Prune, own↔minimalist↔combined transitions, all three window shapes) exercised under shadow on the daily driver, with zero unexplained divergences. Developer confirms before P18.06 begins.
