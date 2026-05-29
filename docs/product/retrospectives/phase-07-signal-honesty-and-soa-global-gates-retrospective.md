# Phase 07 Retrospective — Signal Honesty and SoA Global Gates

## Scope delivered

Five PRs (P7.01–P7.05) on the `phase-07` stacked branch.

- **P7.01**: Schema v4 vocabulary — 19-state enum, drop `work_mode`, row-map rename + placeholders (TS + Swift). [PR #76](https://github.com/cesarnml/codogotchi/pull/76)
- **P7.02**: Hook-binary pure classifier — dropped `events.ndjson` reader, full §7 read/explore buckets. [PR #77](https://github.com/cesarnml/codogotchi/pull/77)
- **P7.03**: Terminal failure parity — `StopFailure` + Cursor `postToolUseFailure` classification. [PR #78](https://github.com/cesarnml/codogotchi/pull/78)
- **P7.04**: Renderer `gate.json` consumer — `GateJsonReader` + merge resolver wired into poll loop. [PR #79](https://github.com/cesarnml/codogotchi/pull/79)
- **P7.05**: Docs + retrospective — `gate-json.md`, `animation-state-vocabulary.md` v4, retire `soa-event-feed.md`, update README.

The 19-state closed schema-v4 enum, `gate.json` sidecar consumer, renderer-side merge resolver, and 6-tier animation model are now the durable architecture. Hook binary is a pure platform-event classifier. Temporary placeholder rows (`green_tdd`→2, `red_tdd`→3, `open_pr`→4, `record_review`→8) bridge the gap until the SoA spritesheet ships.

## What went well

**Atomic vocabulary ticket (P7.01) with coherent enum both sides.** Doing TS + Swift + fixtures in one ticket avoided a broken intermediate state where the hook emits states the renderer refuses. This was P6.01 precedent applied correctly. The cross-language consistency check (19 TS strings ↔ 19 Swift rawValues) was the right invariant to make explicit in the Red tests, not discovered later.

**Pure classifier removal was clean.** P7.02 removed 766 lines of SoA tail-reading machinery without any edge-case breakage because the tests for the retained behavior (Read streak, Bash buckets, Stop classification) were already in place. The deletion was safe because the scope was explicit: remove one code path, leave everything else unchanged.

**Subagent review caught a real bug (P7.04).** The `isExpired` returning `false` for unparseable dates was a genuine security-quality defect — a corrupt `expires_at` would have locked the renderer into an active gate state indefinitely. The subagent found it; the primary agent patched it before publication. The three-phase review gate (write prompt → subagent runs → primary patches) worked as designed.

**Gate.json path derivation from pollingTarget.** Using `config.pollingTarget.deletingLastPathComponent().appendingPathComponent("gate.json")` avoided needing to thread a separate config value through `DemoConfig`. In demo mode the file simply doesn't exist → GateJsonReader returns nil → resolver falls through. Clean design with no extra config surface.

## Pain points

**Xcodegen regeneration required for new Swift source files (avoidable waste).** The `Codogotchi.xcodeproj/project.pbxproj` is not auto-updated when files are added to the filesystem. The new `GateJsonReader.swift` was silently excluded from compilation until `xcodegen generate` was run. The test suite "passed" on the first run at 236 tests because the test file was also excluded. This is a developer trap: a passing CI that never ran the new tests.

Root cause: the project uses `xcodegen` with `project.yml` but `xcodegen generate` is not wired into the test/build commands. The fix is to add a `prebuild` step in `package.json`'s `mac:test` script that runs `xcodegen generate` before `xcodebuild ... test`.

**P7.03 subagent added `---` separators in its report despite template prohibition.** The `---` horizontal rules shifted the parser's section recognition and triggered `reconcile-subagent-review` Condition B (false positive). Resolved by recording a `deferred` row with an explanation. The upstream template warning about `---` clearly wasn't strong enough enforcement — the subagent ignored it.

## Surprises

**`StopFailure` is a separate hook from `Stop` in Claude Code.** In v3, the hook only registered `PreToolUse` and `Stop`. Claude Code fires `StopFailure` as a distinct event for API errors — it does not fire `Stop` too. The old classifier only caught failure via `is_error: true` on tool-use events and `stop_reason: max_tokens` on Stop. Any `StopFailure` event (rate-limit, auth, billing, server error) was previously undetected and produced `idle`. This was a silent reliability gap now covered.

**`postToolUseFailure` `is_interrupt` semantics.** Cursor fires `postToolUseFailure` for both user-initiated interrupts (`is_interrupt: true`) and real tool failures (`is_interrupt: false`). The distinction is important: treating a user interrupt as `errored` would mislead the pet animation. The `is_interrupt !== true` guard correctly handles the absent-field case too (undefined → not true → errored) since absent means "not a user interrupt."

**The `expiry=false on unparseable date` bug pattern.** In `isExpired`, the fallthrough return value when neither ISO 8601 parse pass succeeds should be `true` (expired) not `false` (unexpired). Every TTL-style "return false on parse failure" function is a latent "activates indefinitely on corrupt data" bug. The fix is the right mental model for all future TTL predicates in this codebase: **unparseable expiry = already expired**.

## What we'd do differently

**Wire `xcodegen generate` into the build pipeline before it bites another phase.** The root cause is clear: new Swift files require xcodeproj regeneration, and nothing enforces this. Adding `xcodegen generate` to the `mac:test` and `mac:build` scripts in `package.json` would catch this automatically. We accepted the manual step in Phase 07; it should not survive to Phase 08.

**Subagent report format enforcement.** The `---` separator issue in P7.03 was a subagent non-compliance despite explicit instructions. A future improvement would be a post-processing step in the CLI runner that strips or rejects `---` in reports before persisting, or that surfaces a format warning so the primary agent can request a corrected report.

## Net assessment

Phase 07 delivered its stated goals: the hook is a pure classifier, the renderer reads `gate.json`, the 19-state v4 enum is consistent across contracts/hook/Swift, `work_mode` and `gate_badge` are gone. The temporary placeholder rows and flat-3m gate behavior will generate follow-up decisions once real art and delivery data land, but the durable architecture is in place.

The `expiry=false` bug found by subagent review is the highest-value outcome of the review gate: a subtle failure mode that would have produced invisible long-lived gate activations in production. One real bug caught before PR publication justifies the review overhead for the full phase.

## Follow-up

- Add `xcodegen generate` to `mac:test` and `mac:build` scripts in `package.json` before Phase 08 branches. This is a one-line fix with no risk.
- Remove temporary placeholder rows (`green_tdd`→2, `red_tdd`→3, `open_pr`→4, `record_review`→8) and replace with dedicated gate art when `codogotchi-soa-spritesheet.webp` ships.
- Wire `waiting_for_input`/`PermissionRequest` hook events in the platform-hooks phase.
- Add the TTL-predicate contract to `docs/contracts/animation-state-vocabulary.md`: "Any TTL-style predicate that cannot parse its expiry timestamp MUST return expired, not unexpired."
- Phase 17 (SoA gate writer) must be validated against `gate.json` contract in `docs/contracts/gate-json.md` before Phase 08 builds on top of it.

---

_Created: 2026-05-30. PRs #76–#79 open (pending closeout)._
