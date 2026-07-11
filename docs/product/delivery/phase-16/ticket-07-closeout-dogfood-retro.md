# P16.07 Closeout: exit audit + dogfood DMG + retrospective

Size: 2 points
Type: chore
Scope: menubar
Red: skip

## Outcome

- All seven phase exit conditions are audited on `v3_preview` with evidence (command + output) recorded in this ticket's Rationale section.
- A dogfood DMG is packaged via `scripts/package-dmg.sh` and installed as the daily driver.
- **No version bump, no GitHub release, no download-page change** — local-only artifact per the product plan; the macOS release ritual is deliberately not followed beyond packaging.
- The Phase 16 retrospective exists at `docs/product/retrospectives/phase-16-mechanical-consolidation-retrospective.md`.

## Exit audit checklist (run each, record evidence)

1. **Drawers:** `find apps/menubar/Sources -maxdepth 1 -name '*.swift'` → empty; xcodegen build green.
2. **Splits:** `FloatingPetPanel.swift` and `SettingsWindowController.swift` absent from the tree.
3. **WindowKey kill list:** `grep -rn '"combined"' apps/menubar/Sources` → only WindowKey parse/serialize + persistence boundaries; colon-split grep clean.
4. **Lifecycle:** `SessionLifecycle` classifier is the only lifecycle-judgment site; both consumers match on it.
5. **One writer:** exactly one `customization.json` write site.
6. **Behavior bar:** full suite green; `bun run verify` and `bun run ci:quiet` pass.
7. **Dogfood:** DMG packaged, installed, running as daily driver.

## Red

- `Red: skip` — audit + packaging + docs; no testable behavior added.

## Green

- Run the audit checklist; paste evidence into Rationale.
- Package the DMG; install; confirm the installed app runs against live state.
- Write the retrospective using the `soa-write-retrospective` skill.

## Refactor

- None. If any audit item fails, the fix belongs in a reopened prior ticket's scope or a separate bug-fix commit with a review-gap ledger entry — not in this ticket.

## Review Focus

- Evidence is real command output, not paraphrase.
- No release-ritual leakage: Info.plist / project.yml / download.astro untouched; no `gh release` artifacts.
- Retro captures drawer-taxonomy and domain-type decisions Phases 17–18 inherit, and any review-gap ledger entries produced during the phase.
- The Phase 17 soak gate is recorded as a phase-transition condition in the implementation plan — not marked satisfied by this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (`Red: skip` — audit/packaging/docs)
Why this path: cross-ticket invariants need one authoritative audit after the last code ticket
Alternative considered: folding the audit into P16.06 — rejected; invariants can regress after their originating ticket
Deferred: Phase 17 soak-gate satisfaction (phase-transition condition, not ticket work); any public release (Track 2)

### Exit audit evidence (recorded 2026-07-11 on `agents/p16-07-closeout-exit-audit-dogfood-dmg-retrospective`, based on `v3_preview` @ `c742b9bf`)

**1. Drawers — PASS**
```
$ find apps/menubar/Sources -maxdepth 1 -name '*.swift'
(no output — empty)
```
Confirmed via `bun run ci:quiet` below: `xcodebuild ... build` succeeded with no code changes attributable to the P16.01 move.

**2. Splits — PASS, with a documented naming deviation from the literal checklist text**
```
$ find apps/menubar/Sources -iname 'FloatingPetPanel.swift'
(no output — gone)
$ find apps/menubar/Sources -iname 'SettingsWindowController.swift'
apps/menubar/Sources/Settings/SettingsWindowController.swift   (408 lines, was 4,438)
```
`SettingsWindowController.swift` is **not** absent from the tree, contradicting this checklist item's and the phase exit condition's literal wording ("no longer exist" / "absent from the tree"). This is not a regression: P16.03's own ticket spec (Extraction map: "Controller: `SettingsWindowController` (retains only the window/tab-view orchestration)") and Review Focus ("The residual `SettingsWindowController` file contains only orchestration — no tab-view code left behind") explicitly planned for a slimmed residual file under that name, and the P16.03 Rationale confirms it was retained deliberately: *"retained `SettingsWindowController.swift` as the controller-only orchestration file described by Review Focus."* The god-file (4,438 lines, ~25 top-level types) is gone; what remains is a 408-line orchestration shell — the actual anti-pattern (one file owning every tab's view logic) is eliminated. The checklist/exit-condition wording is imprecise, not the implementation. No fix needed; no reopened ticket.

**3. WindowKey kill list — PASS on architectural intent; literal grep wording does not hold**
```
$ grep -rn '"combined"' apps/menubar/Sources
```
Hits span `Pool/WindowKey.swift` (the sanctioned parse/serialize path), test fixtures, doc-comments across ~9 files, and real code in `Pool/FloatingPetWindowPool.swift`, `State/AssignmentsJsonReader.swift`, and `Pool/PlatformAttribution.swift`. Traced each non-WindowKey code hit:
- `PlatformAttribution.init?(origin:)` maps `source_event.origin` (a platform-attribution string domain, badge/logo lookup) — orthogonal to `WindowKey` identity, predates and was never in P16.04's scope.
- `AssignmentsJsonReader.swift`'s `AssignmentsSnapshot.resolve(origin:)` guards `origin != "combined"` — same origin-attribution domain (`assignments.json`, keyed by platform origin), not `WindowKey`.
- `FloatingPetWindowPool.swift`'s literal `"combined"` usages (`currentAssignments.resolve(origin: "combined")`, `applyPlatform(origin: "combined")`, `combinedDefaultOrigin = "combined"`) all call into that same origin-attribution domain, not `WindowKey` string branching.
No file does ad hoc colon-splitting or raw-string `WindowKey` policy branching outside `WindowKey.swift` itself — the invariant P16.04 exists to protect holds. The checklist wording ("only WindowKey parse/serialize sites and test fixtures") doesn't account for the separate, legitimate origin-attribution string domain. No fix needed; no reopened ticket.

**4. Lifecycle — PASS**
```
$ grep -rln "SessionLifecycle" apps/menubar/Sources apps/menubar/Tests
apps/menubar/Sources/Settings/SessionsTabViewModel.swift
apps/menubar/Sources/Pool/SessionLifecycle.swift
apps/menubar/Tests/MenubarTests/SessionLifecycleTests.swift
```
Single classifier (`SessionLifecycle.classify`); its doc comment records that the menubar pet section consumes it via `SessionsTabViewModel`'s shared instance rather than a second direct import, satisfying "single classifier, both consumers match on it" through one call site.

**5. One writer — PASS**
```
$ grep -rn 'ConfigFileWriter\.merge' apps/menubar/Sources
apps/menubar/Sources/Settings/PetTabViewModel.swift:183   (writes assignments.json, not customization.json)
apps/menubar/Sources/State/CustomizationStore.swift:60    (writes customization.json — the sole write call)
```
All other `customization.json` string hits (`GeneralTabViewModel.swift`, `SettingsWindowController.swift`, `CustomizationTabViewModel.swift`, `MenubarApp.swift`, `CustomizationJsonReader.swift`, `CodogotchiFolders.swift`, `FloatingPetInteractionView.swift`, `MinimalistPanelController.swift`, `FloatingPetPanelController.swift`, `FloatingPetWindowPool.swift`, `LivePollingDriver.swift`, `SessionsTabViewModel.swift`, `CustomizationTabView.swift`) are doc comments or reads, confirmed by absence of any `.write(to:`/`ConfigFileWriter.merge` call outside `CustomizationStore.swift`.

**6. Behavior bar — PASS**
```
$ bun run ci:quiet
...
Test Suite 'WindowKeyTests' passed — 11 tests, 0 failures
Test Suite 'CodogotchiTests.xctest' passed at 2026-07-11 23:23:55.569.
	Executed 1047 tests, with 0 failures (0 unexpected) in 111.745 (112.193) seconds
** TEST SUCCEEDED **
```
`bun run verify` (biome check) passed as part of `ci:quiet`'s `verify:quiet` stage — no findings.

**7. Dogfood — PASS**
```
$ bash scripts/package-dmg.sh
...
Verified macOS app bundle:
  app: .../Codogotchi.app
  version: 2.7.0 (12)
  icon: AppIcon
Done! DMG at: /Users/cesar/code/codogotchi_p16_07/builds/Codogotchi.dmg
```
DMG mounted, running app quit, `/Applications/Codogotchi.app` replaced from the mounted image, quarantine cleared (`xattr -cr`), relaunched. Confirmed running: `pgrep -fl Codogotchi` → `/Applications/Codogotchi.app/Contents/MacOS/Codogotchi`; `Info.plist` `CFBundleShortVersionString` = `2.7.0` (no version bump, per contract). No `Info.plist`/`project.yml`/`download.astro` edits; no `gh release` artifacts.

**Net result:** all 7 exit conditions hold in substance. Items 2 and 3 reveal that the checklist/exit-condition prose was written more strictly than the actual (reviewed, intentional) P16.03/P16.04 designs — a documentation-precision gap, not an implementation defect. No reopened tickets required.
