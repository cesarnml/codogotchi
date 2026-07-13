# Phase 18 Exit Audit

Audit date: 2026-07-13

Audited branch: `agents/p18-07-old-pipeline-deletion-and-closeout`

## 1. `derive` → `diff` → `apply` is the update path; old imperative pipeline deleted — PASS

- `final class LegacyPoolEngine` (the entire pre-P18.06 imperative pipeline,
  ~1490 lines) and `enum PoolEngine` are deleted from
  `FloatingPetWindowPool.swift` (2002 → ~500 lines). `FloatingPetWindowPool`
  is now the sole class: input assembly, stored `PoolMemory`, the
  `derive`→`diff`→`apply` composition in `update(snapshot:)`, the public
  surface, and the user-action two-limb methods.
- The `CODOGOTCHI_POOL_ENGINE` rollback flag, `activeEngine`,
  `poolEngineEnvironment`, `shadowDivergenceHandler`, and
  `shadowTickInputPerturbation` are deleted along with every
  `activeEngine == .new ? … : legacy.…` branch.
- Shadow-only production wiring is deleted: `NoOpStubWindowController.swift`,
  `RecordedPushDesiredWindowReconstruction.swift`,
  `Derive/ShadowTickFingerprint.swift`, and the shadow-tick test file
  `FloatingPetWindowPoolShadowTickTests.swift` (its whole premise no longer
  exists). `MenubarApp.swift`'s `shadowDivergenceHandler: { ShadowDivergenceLogger.log($0) }`
  init argument — the last production shadow wiring — is removed.
- Structural evidence (tip of the P18.07 branch, commit `3959bb89`):
  ```
  grep -rn "LegacyPoolEngine\|PoolEngine\b\|CODOGOTCHI_POOL_ENGINE\|activeEngine\|poolEngineEnvironment\|shadowDivergenceHandler\|shadowTickInputPerturbation\|runShadowTick\|NoOpStubWindowController\|RecordedPushDesiredWindowReconstruction\|ShadowTickFingerprint" apps/menubar/
  ```
  → 0 hits.
- `RecordingFloatingPetWindowControllingProxy.swift` and
  `PoolShadowComparator.swift` (and `ShadowDivergenceLogger.swift`) survive
  as standalone, directly-tested utilities per the ticket's explicit
  allowance ("recording proxy and comparator may survive only where tests
  use them") — no production call site constructs or invokes them anymore.
- `FloatingPetWindowPool`'s existing public surface (`setVisible`,
  `pruneSession`, `hideAllOtherWindows`, `resetPromptTimer`, `sessionNumber`,
  `sessionDisplayLabel`, `controller(for:)`, `activeOrigins`,
  `blockedOrigins`, `pendingSessionKeys`, `ttlDismissedWindowKeys`,
  `replacePet`, `clearAttentionBubbles`,
  `pruneHiddenKeysWithoutBackingSlice`, …) is unchanged; `MenubarApp` and
  menu wiring were not touched beyond removing the dead shadow-handler
  argument.

## 2. `derive` is pure, no AppKit imports (automated purity gate) — PASS

- Purity gate test confirmed present and passing:
  `apps/menubar/Tests/MenubarTests/Derive/PoolDerivePurityGateTests.swift`
  (`testNoAppKitImportUnderPoolDerive`), executed as part of `mac:test`
  (part of `bun run ci:quiet`). The gate is unmodified by this ticket and
  remains in CI permanently.
- `derive` continues to consume `SessionLifecycle` and `WindowKey` only.

## 3. `DesiredWindows` + diff directives require zero additional policy in `apply` — PASS

- The step-mapping artifact is the doc-comment table in
  `apps/menubar/Sources/Pool/Derive/PoolDerive.swift` (`Step 1` through
  `Step 8`, including sub-steps 3b/5b/6a/6a2/6b/6c), built across
  P18.01–P18.03 and reviewed line-by-line against the deleted `update()`
  source during the P18.03 subagent-review pass
  (`docs/product/delivery/phase-18/reviews/P18.03-subagent-review.report.md`).
  That review surfaced one documentation-drift gap (the transient-gap
  branch and shared-timer observation were behaviorally transcribed but not
  named in the step map's prose) — a doc-comment gap, not a missing
  behavior; no `apply`-side policy decision was found.
- `PoolApply.swift` is mechanical effect application only; its doc comments
  were cleaned of dead `LegacyPoolEngine` references in this ticket with no
  behavior change.

## 4. Named table-driven tests cover Phase 15 QC gap classes; full suite green — PASS

- Gap-class coverage: `PoolDeriveSelectionTests.swift` (cap/eviction,
  grandfather admission, hide-while-capped), `PoolDerivePushTests.swift`
  (mode-transition teardown, combined folding), `PoolDeriveTests.swift`
  (core tick derivation), `PoolDiffTests.swift`, and
  `PoolMemorySessionAllocatorTests.swift`, all pre-existing from P18.01–03
  and untouched by this ticket except where they directly exercised deleted
  legacy/shadow machinery.
- `FloatingPetWindowPoolTests.swift`: removed 2 dead engine-selection tests
  (`testDefaultEngineSelectionIsNewEngineDrivesOldShadows`,
  `testLegacyEnvVarSelectsOldEngineAsAuthoritative` — their premise, the
  `CODOGOTCHI_POOL_ENGINE` flag, no longer exists); updated 2 title-resolution
  tests whose own comments documented their "2, not 1" call-count assertions
  as a temporary P18.06→P18.07 soak-window artifact expected to disappear
  with this ticket — now assert the correct single-resolution count.
- `bun run verify:quiet`: pass.
- `bun run ci:quiet`: pass — `bun test` 628 pass / 0 fail;
  `mac:test` (xcodebuild) 1146 tests, 3 skipped, 0 failures. The 3 skips are
  pre-existing `XCTSkip("P18.06 known gap: …")` markers for genuine,
  previously-tracked new-engine gaps (last-active immunity / TTL grace
  across total snapshot absence) unrelated to this ticket's deletion —
  tracked separately for post-landing QA, not a regression introduced here.

## 5. Pre-cutover and post-cutover reversed-shadow soaks, every divergence resolved — **DEVELOPER-WAIVED, NOT INDEPENDENTLY VERIFIED**

- The implementation plan's binding stop condition (**P18.06 → P18.07
  gate**) requires the rare-branch checklist (session cap overflow +
  eviction, grandfather admission both directions, hide-while-capped,
  manual Prune, own↔minimalist↔combined transitions, all three window
  shapes) to be exercised against the reversed shadow on the dogfood daily
  driver, with zero unexplained divergences, before deletion starts.
- No soak-summary doc, divergence-log artifact, or rationale entry
  recording this checklist's result exists anywhere under
  `docs/product/delivery/phase-18/` as of this audit.
- The developer was asked directly whether this checklist had been run
  and explicitly answered **"No, waive the gate anyway"** during this
  session, accepting the risk and stating any unexpected behavior will be
  patched after landing on `v3_preview`.
- **This condition is not demonstrated true by evidence.** It is recorded
  here as developer-waived rather than PASS so the gap is visible to future
  readers of this audit, not silently absorbed into a PASS. Any residual
  behavior divergence between the old and new pipelines that would have
  been caught by this soak remains an open risk on `v3_preview` after this
  phase closes.

## 6. Local dogfood DMG packaged, installed, running as daily driver — PASS

- Packaged with `scripts/package-dmg.sh` from the P18.07 branch tip
  (commit `3959bb89`); staged bundle verification passed.
- Artifact: `builds/Codogotchi.dmg`.
- SHA-256: `1223960a877b6e4b9e8432f8a2f4770bc1dc93fa995e07f86ef55e59cf20e5ee`.
- Installed to `/Applications/Codogotchi.app`, version 2.7.0 (build 12,
  unchanged — no version bump, matching the Phase 17 precedent), replacing
  the previously-running instance. Process inspection confirmed the newly
  installed binary running (PID 95051) after relaunch.
- No version bump, GitHub release, or download-page change was made.

## Summary

5 of 6 exit conditions are demonstrably PASS with structural/test evidence.
Condition 5 (the reversed-shadow soak) is explicitly developer-waived, not
verified — see that section for the exact scope of the accepted risk.
