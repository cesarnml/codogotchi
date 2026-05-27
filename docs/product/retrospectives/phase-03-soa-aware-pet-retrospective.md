# Phase 03 — SoA-aware pet retrospective

Source plan: [`docs/product/plans/phase-03-soa-aware-pet-animation-coverage.md`](../plans/phase-03-soa-aware-pet-animation-coverage.md).
Delivery plan: [`docs/product/delivery/phase-03/implementation-plan.md`](../delivery/phase-03/implementation-plan.md).

## Scope delivered

Tickets P3.01 → P3.08 (8/8) shipped as a stacked PR chain on `agents/p3-*`
branches, PRs [#35](https://github.com/cesarnml/codogotchi/pull/35) through
[#44](https://github.com/cesarnml/codogotchi/pull/44). Delivered:
- `schema_version` bumped to 2 in the hook and the Swift reader, with a new
  `v2`-only `ActivityState` pair (`requesting_input`, `errored`) and new
  `source_event` fields in `state.json`;
- `ActivityState` extended from 4 to 15 closed-enum cases;
- Codex sheet expanded from 4 to 6 rows (`waiting`, `requesting_input`, `errored`
  wired from existing spritesheet rows);
- `CodogotchiPet` loader for the new 24-column × 9-row spritesheet owned by
  codogotchi, serving 9 SoA-gate states;
- Composite resolution in `MenubarRenderer` (Codex sheet first → codogotchi
  sheet second → idle fallback);
- `PetConfig` reading `~/.codogotchi/config.json` `{ "pet": "<name>" }` with
  `CODOGOTCHI_HOME` override and a compiled-in `"maew"` default;
- "Reveal pet folder" (`~/.codex/pets/`) as the second menu item in `MenubarMenu`;
- Demo mode extended from 4 to 15 states, with 11 new `schema_version: 2`
  fixtures and a `CODOGOTCHI_DEMO_FRAME_MS` env override for frame timing;
- Phase 03 validation runbook at `docs/runbooks/phase-03-validation.md`.

## What went well

- **Composite resolution pattern was the right shape.** The
  Codex-sheet-first → codogotchi-sheet-second → idle-fallback ordering
  in `resolveFrames(for:)` is small (15 lines) and testable in isolation.
  The `SpriteSource` enum cleanly drives the per-frame interval in
  `restartTimer()` without the renderer needing to know which loader won.
  When the codogotchi spritesheet is absent, the renderer's existing idle
  fallback kicks in without any new code path — the soft-degrade for missing
  assets is "free" from the pattern's structure.
- **Demo mode as the Phase 03 entry point.** Extending the demo cycle to
  15 states before any of the new sprites were validated in live mode
  preserved the Phase 02 lesson: prove the rendering pipeline against
  fixtures before pointing it at real hook output. `CODOGOTCHI_DEMO_FRAME_MS`
  was a small addition that immediately paid for itself during manual
  validation — slowing frames to 83 ms made per-frame sprite inspection
  straightforward.
- **`PetConfig` stayed a single function.** The grilling correctly held
  the line at "one key, one reader, done." No `Codable` struct, no
  `schema_version` on the config file (deferred per the plan), no
  abstraction layer for "configurable string values." The result fits in
  30 lines and the `getenv()` seam made tests straightforward without
  mocking `ProcessInfo`.
- **Subagent review found real issues.** Across the 6 code tickets, the
  adversarial review passes found: the missing `NSLog` in the
  codogotchi-sheet soft-degrade branch (P3.04), a weak pixel equality
  assertion that could have hidden row-mapping errors (P3.04), the stale
  4-state docstring (P3.06), and the missing empty-string fallback test
  (P3.05). These are the kind of correctness gaps that survive code
  review when the reviewer is also the author. The review-then-patch
  cycle added roughly one commit per ticket but none required redesign.

## Pain points

- **`ProcessInfo.processInfo.environment` is a frozen snapshot.** The
  P3.05 red commit was designed to test `CODOGOTCHI_HOME` via `setenv()`
  in-process, which does not work with `ProcessInfo.processInfo.environment`.
  Three tests failed at Green because `writeConfig` wrote to
  `dir/.codogotchi/config.json` while `PetConfig.configURL()` looked for
  `dir/config.json` — the two assumptions about what `CODOGOTCHI_HOME`
  means (user home vs. codogotchi home) were inconsistent between the
  helper and the implementation. Fixing required both switching to `getenv()`
  and correcting the helper. The lesson: `ProcessInfo.processInfo.environment`
  is a one-way door; write env-sensitive code against `getenv()` from day 1
  if tests need to set env vars in-process.
- **`project.pbxproj` editing is still manual and painful.** P3.04 added
  two new Swift source files (`CodogotchiPet.swift`, `CodogotchiPetTests.swift`)
  that required manually editing `Menubar.xcodeproj/project.pbxproj` with
  hand-generated hex IDs. The same happened for P3.05's `PetConfig.swift`.
  This is inherent to Xcode-native projects without a codegen step.
  Mitigations: keep new files small in number, batch new files per ticket,
  and copy adjacent PBX block shapes exactly. Phase 06's multi-pet catalog
  will add more sources; if it exceeds three new files, spend the time to
  automate the `pbxproj` edits.
- **`DemoModeTests.swift` needed two test updates after extending the
  cycle.** `testCycleDriverEmitsFloorStatesInCycleOrder` and
  `testCycleDriverLoopsBackToIdleAfterCelebrating` both hardcoded the
  4-state cycle assumption. After extending to 15, both were wrong: the
  first 4 ticks no longer land on `[.idle, .implementing, .runningTests, .celebrating]`.
  These were updated in Green but required careful thought about which
  ticks to assert. This is avoidable — the red tests could have been
  written against the cycle *array contents* (index-based) rather than
  the *emitted state sequence* (tick-sequence), which would have survived
  the extension.

## Surprises

- **`getenv()` vs. `ProcessInfo.processInfo.environment` is a practical Swift
  gotcha.** `ProcessInfo.processInfo.environment` is captured at process launch
  and never updated. `getenv()` is the live POSIX snapshot and reflects
  in-process `setenv()` calls. The two are equivalent for production code
  (the environment does not change post-launch in production), but diverge
  completely in test contexts where `setenv()` is the natural seam. Swift
  documentation surfaces this subtly — the property reads as a simple
  dictionary accessor, not as a snapshot-at-launch.
- **The folder reference in `project.pbxproj` means fixture JSON files are
  included automatically.** The entire `Fixtures/state-json/` directory is
  tracked as a PBX folder reference (`lastKnownFileType = folder`), so adding
  new JSON files to the directory requires no `pbxproj` edits. This was
  already the case for Phase 02's four fixture files; the 11 new P3.06
  fixtures inherited this behavior for free. New Swift source files require
  explicit `pbxproj` edits; resources organized as folder references do not.
- **WebP decodes correctly on macOS 13+ via `NSImage`/`CGImage` without any
  additional ImageIO work.** The codogotchi spritesheet arrived as a WebP
  file and loaded cleanly through the same `NSImage(contentsOfFile:)` path
  as the Codex sheet. This was an implicit assumption in the P3.04 design
  that could have required a fallback path; it did not.

## Phase 03 lessons for follow-up phases

### Schema v2 bump precedent

Phase 03 is the first version bump after the contract's initial lockdown.
The policy's "further changes require a new ticket" clause was invoked: P3.01
was that ticket. The bump is additive — two new `ActivityState` values, new
optional `source_event` fields — and the renderer's forward-compat clause
(refuse `schema_version > EXPECTED`) protected the Phase 02 path during the
transition. The lesson: the schema-version mechanism works as designed for
additive changes. A breaking change (removing or renaming a field) would
require a harder coordination sequence across the hook and the renderer, and
would need its own design ticket before implementation.

### Codogotchi spritesheet commissioning learnings

The spritesheet (`codogotchi-spritesheet.webp`) was commissioned externally.
The Phase 03 budget estimated ~$11 for AI-generated sprites; the actual cost
came in within that range. Turnaround was approximately one iteration cycle.
Frame-quality notes: the 24-frame 167 ms/frame cycle produces a ~2-second
animation loop, which is visually smooth at the 22pt menu bar height. The
sprite rows selected per state (see the Codogotchi Sheet table in
`docs/contracts/animation-state-vocabulary.md`) are visually distinct.
Carry-forward for Phase 06's multi-pet catalog: commissioning should specify
the 24×9 grid format and `schema_version`-keyed row assignments upfront. The
P3.04 `CodogotchiPet.rowMap` is the canonical reference; new pets should ship
with a `pet.json` that references the sheet and the row map drives which
states it serves.

### Cross-repo soul dependency on SoA

Phase 03 depended on Phase 15's SoA event emission contract — specifically the
nine event names (`ticket_started`, `flow_state_entered`, `risky_diff_detected`,
`pr_review_window_opened`, `ticket_completed`, `review_clean_recorded`,
`stage_advanced`, `subagent_invoked`, `verification_failed`) that drive the
nine codogotchi-sheet states. Phase 15 shipped the contract via
`docs/contracts/soa-event-feed.md` and the codogotchi hook consumes it without
modification. The producer/consumer contract held up: the hook is a read-only
consumer of `.soa/events.ndjson` and never writes there. The dependency was
the right architectural decision — codogotchi should not know when SoA gates
fire; SoA should emit events that codogotchi reads. The one bump was that
Phase 03's delivery required Phase 15's events to be present in `.soa/events.ndjson`
for manual validation; the synthetic event recipes in `docs/runbooks/phase-03-validation.md`
are the workaround for validation without a live SoA run.

### Lockstep vs. renderer-first release

Phase 03 shipped lockstep (n=1: single owner, single machine). The
renderer-first default for n>1 external consumers: ship the new renderer
states before updating the hook to emit them. The renderer's unknown-state →
`idle` fallback protects the production path — a renderer that knows about
`nervous` but receives no `nervous` events from the hook simply stays on idle.
Deploying renderer-first means no user ever sees "wrong state" during the hook
rollout window. For n>1 consumers (Phase 06+), the release order is:
1. Renderer update (new states land, fall back to idle until hook catches up).
2. Hook update (new events begin emitting; renderer picks them up within one poll).
3. Validation window.

## Phase 02 open strategic question — closed

The Phase 02 retrospective recorded this open question: _"Richer pet format vs. atlas extension vs. premium-tier image generation."_

**Empirical answer: atlas extension.** Phase 03 picked the atlas extension path:
- A new codogotchi-owned spritesheet (`codogotchi-spritesheet.webp`, 24×9) alongside the existing Codex sheet.
- The Codex sheet retained its existing 8×9 layout; only new rows were added via the `rowMap` expansion.
- No richer pet format (no `animation` block in `pet.json`); no premium-tier generation beyond the commissioning step.

This answer is provisional for n=1. Phase 06's multi-pet catalog will re-open the format question with real multi-pet data: does every pet need its own codogotchi sheet, or is one canonical sheet shared? The atlas extension approach makes the question concrete — the cost of "one sheet per pet" is visible now.

## Follow-up

- **Owner runs the validation runbook (`docs/runbooks/phase-03-validation.md`).**
  Triggers all four rare-state synthetic events, captures transition log evidence,
  confirms demo mode cycles all 15 states visually. Phase 03 EC3 and EC4 require
  owner attestation.
- **Phase 06 (multi-pet catalog) inherits `CodogotchiPet.rowMap` as the extension
  surface.** Adding a second pet means either a second `rowMap` or a format
  extension in `pet.json`. The Phase 06 grilling should open with this question.
- **`pbxproj` automation for new sources.** If Phase 06 adds more than two new
  Swift source files, invest in a script (e.g., using `xcodegen` or a minimal
  PBX patching script) rather than hand-editing hex IDs again.
- **README setup section now reflects Phase 03's user workflow.** Pet name is
  configurable via `~/.codogotchi/config.json`; "Reveal pet folder" in the
  menu bar opens `~/.codex/pets/`. See updated README for the post-Phase-03
  install path.

---

_Created: 2026-05-24. Phase 03 stack open in PRs #35–#44; closeout pending developer approval._
