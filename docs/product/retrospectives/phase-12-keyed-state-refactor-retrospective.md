# Phase 12 — Keyed-State Refactor Retrospective

## Scope delivered

Five tickets shipped on `v2_preview`, stacked in order:

- **P12.01** — keyed-slice contract + reducer interface: `sliceEntrySchema`, `globalAggregate`, `perPlatform` (pure, unwired), `SliceReducer<T>` interface (PR [#126](https://github.com/cesarnml/codogotchi/pull/126))
- **P12.02** — CLI slice-directory writer: `writeSliceAtomic`, `deleteSliceBestEffort`, `sliceDirPath`/`sliceFilePath` in `hook-binary.ts` (PR [#127](https://github.com/cesarnml/codogotchi/pull/127))
- **P12.03** — Swift slice-directory reader + render: `StateJsonReader.readDirectory(at:)`, `SlicePayload` struct, `EXPECTED_STATE_SCHEMA_VERSION` bumped to 7, `LivePollingDriver` default reader switched (PR [#128](https://github.com/cesarnml/codogotchi/pull/128))
- **P12.04** — `/sync` shared-secret hardening: `SYNC_SHARED_SECRET` env-var check in `convex/http.ts`, `syncSecret` header injection in CLI `sync.ts` (PR [#129](https://github.com/cesarnml/codogotchi/pull/129))
- **P12.05** — contract docs + this retrospective (P12.05 PR)

All PRs target `v2_preview`. Behavior parity with v1.1.1 confirmed via 15+ characterization tests in P12.03 (564 Swift tests pass). No web, Settings, `.son-of-anton`, or spritesheet files touched.

## What went well

**Behavior-invisible gate via characterization tests.** The P12.03 ticket's red step required writing characterization tests — fixtures → exact `ActivityState`/overlay outputs matching v1.1.1. This gave reviewers a machine-verifiable parity proof, not just the claim "it should work the same." The tests also caught the 28-failure regression before green (details in Pain Points) because each fixture → output mapping was named and explicit.

**v2_preview model eliminated dual-write entirely.** The grill-me decision to target `v2_preview` and not ship intermediate DMG releases paid off concretely: there was no in-the-wild skew window to protect, so no dual-write scaffolding was needed. That removed roughly 2–3 days of complexity from P12.02–03. The additive dual-write path was scaffolding for a problem that literally cannot occur pre-GA; naming this explicitly in the implementation plan made the tradeoff visible.

**`claude-status-bar` prior art.** Having a documented prior art for the `state.d/<origin>:<session_id>.json` pattern (from the `notes/private/per-thread-vs-per-platform` stance research) meant the architecture was proven before Phase 12 started. No exploration tax was paid during delivery.

**`SlicePayload` fixture reuse.** The insight to omit `schema_version`, `origin`, and `session_id` from the Swift `SlicePayload` decoder struct — because the filename provides keying and the fields are unused by `globalAggregate` — meant every existing old-format fixture file decoded correctly without modification. This kept the 15+ characterization tests from requiring new fixture files, which would have been busywork.

**Cook mode delivery.** Running the full 5-ticket stack in `boundary_mode=cook` meant the orchestrator advanced tickets automatically after each `advance` command without a context-reset prompt between tickets. P12.01 → P12.02 → P12.03 → P12.04 → P12.05 progressed without manual `resume` invocations. The only disruption was context compaction mid-session (P12.03 → P12.04 boundary), which the summary artifact handled cleanly.

**Intra-branch lockstep was clean.** The grill-me decision to bump `STATE_JSON_SCHEMA_VERSION` (TS) and `EXPECTED_STATE_SCHEMA_VERSION` (Swift) to 7 in the same phase, in the same checked-out branch, meant no cross-version mismatch was possible during development. The tests naming both constants (`testExpectedSchemaVersionIsV4` → renamed `testExpectedSchemaVersionIsV5` → assert `== 7`) surfaced any drift immediately at build time.

## Pain points

**28 test failures in P12.03 green step (avoidable waste).** After switching `LivePollingDriver`'s default reader from `StateJsonReader.read(at:)` to `StateJsonReader.readDirectory(at:)`, 28 tests failed because the existing tests wrote to a file path (`target`) but `readDirectory` expected a directory at that path. Root cause: `makeSandboxPath()` was updated to return `state.d/` but the write helpers (`copyFixture`, `writeV5StateJson`) were updated in the same commit rather than atomically in the red step. Had the red step included the write helpers and sandbox path update together, the 28 failures would have been "expected red" rather than a surprise green regression. Going forward: when a sandbox path changes, update all write helpers and the sandbox getter in the same red commit.

**Error-visual test redesign (expected cost, not avoidable).** The directory reader's best-effort slice decoding (`try?` + `guard ... else { continue }`) means `.malformed`/`.schemaNewer` errors cannot be triggered by writing bad files to `state.d/`. Initially tried the file-write approach; it silently produced idle (skipped slices) instead of the expected error visual. The fix — injecting custom `reader: { _ in .failure(.malformed) }` closures via a new `reader` parameter on `makeDriver` — correctly decoupled "how does the driver handle error Results" from "how does the reader produce error Results." This is the right design, but it cost an iteration. The lesson: design injection seams for error paths before writing the error tests, not after hitting the first failure.

**Context compaction across cook boundary.** The session was compacted at the P12.03 → P12.04 boundary (context exhaustion). The summary artifact captured enough context (current ticket, commit SHAs, worktree path, next command) for the continuation session to pick up without questions. Expected cost — cook mode across long sessions will hit compaction. The handoff artifact format handled it; no work was lost.

## Surprises

**`SlicePayload` origin/sessionId omission wasn't in the spec.** The ticket spec described SlicePayload without specifying whether it should have `origin`/`sessionId`. The implementation discovered mid-flight that including them would require adding top-level keys to the existing fixture JSON files (which were written in `state.json` format without `origin`/`sessionId`). The insight — filename provides keying, fields unused by reducer — resolved it. The subagent review confirmed no invariant was broken. Worth documenting here because future slice decoder changes should check: does the new field appear in existing fixture files, or does it need new fixtures?

**Dev-permissive vs fail-closed on P12.04 wasn't pre-decided.** The ticket said "define and document the dev/test behavior explicitly" without specifying which way. The implementation chose dev-permissive (allow through when `SYNC_SHARED_SECRET` is unset) because fail-closed would break existing production syncs and local Convex dev environments simultaneously. The subagent review flagged doc drift (Outcome section still said "fail closed," Rationale said dev-permissive). This is the kind of design decision that should be resolved in the Grill-Me session for the ticket, not discovered during implementation.

**`process.env` mutations work in the convex-test harness.** Setting `process.env.SYNC_SHARED_SECRET` in `beforeEach` and deleting it in `afterEach` within the Bun test runner worked correctly in the `convex-test` harness. This wasn't obvious — the convex-test harness runs httpActions in a Convex-simulated context, but it shares the same Bun process environment. Useful to know: env-var injection is a valid test seam for Convex httpAction guards.

**P12.04 independence from P12.01–03 created an awkward stack dependency.** P12.04 (Convex + CLI only) was stacked on P12.03 (Swift reader) because the phase was sequenced that way in the implementation plan. In hindsight, P12.04 could have targeted `main` directly as a standalone PR — it has no code dependency on P12.01–03 and the shared-secret hardening is immediately production-useful. Stacking it on `v2_preview` means it doesn't reach production until the full v2 closeout.

## What we'd do differently

**Resolve dev-permissive vs fail-closed in Grill-Me, not in implementation.** The P12.04 ticket left the failure mode for "env var unset" as an open implementation detail, which produced doc drift and a subagent finding. For any security gate that has a dev vs production posture distinction, the correct posture should be a Grill-Me decision recorded in the implementation plan — not a mid-implementation discovery. The spec should read "if unset: allow through (dev-permissive)" or "if unset: fail closed," not "define and document the dev/test behavior."

**Consider breaking P12.04 out as a standalone PR on `main`.** `/sync` shared-secret is orthogonal to the keyed-state refactor and immediately production-relevant. Stacking it in the v2_preview phase means it waits for the full v2 closeout. The correct call depends on whether "fold into refactor phase" (to reduce PR count) or "ship to prod immediately" (to close the open-internet write hole) is more important. Neither was wrong in context (the open-internet hole isn't actively exploited) but the trade-off should be named explicitly next time.

**Red step: update write helpers and sandbox path atomically.** When a test's "where do I write my test fixture" path changes, update the write helper(s) and the sandbox path getter in the same red commit so that all 28 "read from wrong location" failures show up as expected red failures, not surprise green regressions.

## Net assessment

Phase 12 achieved its stated goals: behavior-invisible refactor with zero pet/menubar/gate regression, intra-branch writer/reader lockstep at schema v7, and a `(origin, session_id)`-keyed slice-directory model that forms the additive foundation for v2/v3 multi-pet features. The characterization tests (15+ in P12.03) are the durable evidence: a reviewer can read them and confirm the reducer collapses to the same `ActivityState` v1.1.1 produced from the equivalent `state.json`. The `perPlatform` reducer exists as a proven interface with unit tests, ready to wire to render in a later feature phase. The `/sync` shared-secret guard closed the open-internet write hole with a safe, backward-compatible rollout posture.

## Follow-up

- **Triage P12.01–04 subagent advisory observations** via `/soa triage-advisory-observations phase-12` before Phase 13 starts. Key observations: doc drift in P12.04 ticket Outcome (resolved in Rationale, not code), `CODOGOTCHI_SYNC_SECRET` absent from `codogotchi help`, tooltip copy in `LivePollingTooltips` still says `state.json` for error paths.
- **Update `LivePollingTooltips` error path copy** to reflect `state.d/` as the polling target. Low priority (error paths only; correct behavior, wrong string). Natural home: next CLI hygiene pass.
- **Add `CODOGOTCHI_SYNC_SECRET` to `codogotchi help`** or a `codogotchi sync --help` stub. Currently undocumented. Natural home: next CLI hygiene pass.
- **Closeout the P12.01–05 stack onto `v2_preview`** via `/soa closeout-stack` after the P12.05 PR is approved.
- **Plan the v2_preview → main GA migration** as a dedicated phase (not smuggled into a feature phase). The one-time v1.1.1 → v2 migration needs explicit scope and a DMG release.

---

_Created: 2026-06-28. PRs [#126](https://github.com/cesarnml/codogotchi/pull/126), [#127](https://github.com/cesarnml/codogotchi/pull/127), [#128](https://github.com/cesarnml/codogotchi/pull/128), [#129](https://github.com/cesarnml/codogotchi/pull/129) open on `v2_preview`._
