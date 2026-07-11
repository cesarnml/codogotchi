# Phase 16 — Mechanical Consolidation ("Types and Drawers")

> Restructure the menubar target into six layer directories, split the two god-files type-per-file, and introduce the three missing domain types (`WindowKey`, `SessionLifecycle`, `CustomizationStore`) — with zero intentional user-visible change — so Phases 17 and 18 start from grouped files and real types.

## Epic

Track 4 architectural consolidation (Phases 16 → 17 → 18). Product plan: `docs/product/plans/phase-16-mechanical-consolidation.md`.

## Product contract

No user-visible change — that is the contract. When this phase is complete a developer can:

- Find any menubar source file by the layer it belongs to; no Swift file lives at `apps/menubar/Sources/` root.
- Express the origin / origin:session / combined split by matching on `WindowKey` instead of inspecting strings.
- Read the Active/Live/Archived/Pruned lifecycle as a match statement over `SessionLifecycle` with one classifier.
- Trust exactly one write path to `customization.json` in the app target.
- Run the app from a locally packaged dogfood DMG that behaves identically to v2.7.0.

## Grill-Me decisions locked

- **Spine: moves → splits → types → closeout** → splits create files directly in final drawers (no double-moves); type sweeps then edit small focused files with clean blame.
- **Directory restructure is one ticket** → Swift targets have no per-file imports, so the move is compile-neutral by construction; review is table-vs-`git mv` conformance, not 67 diffs.
- **One split ticket per god file; each deletes its file in one PR** → atomic "file no longer exists" exit check; extraction verified by "every removed line reappears verbatim in exactly one new file, modulo access keywords."
- **Sanctioned deviation for splits: `private` → `internal` where file-scoping forced it** → verified by "no new call sites"; the only signature change allowed in the phase.
- **`WindowKey` lands in one ticket, no compatibility shims** → switching pool APIs to the enum makes the type-checker walk every consumer; shims would ship the dual-representation anti-pattern the type exists to kill.
- **Edge-file drawer rule: drawer = who owns the type at runtime, not what the name suggests** → `RPGHUDPanel` + `RPGHUDViewModel` → `Windows/`, `PlatformAttribution` → `Pool/`, `MenubarRenderer` → `App/`, `FloatingPetController` → `Windows/`, `AppState` + `ActivityState` → `State/`.
- **Tests stay flat in `Tests/MenubarTests/`** → suffix naming already solves lookup; a mirror built before the splits would be stale by P16.03; revisit after Phase 18 at the earliest.
- **`SessionLifecycle` is one ticket in `Pool/`, both consumers rewired in the same PR** → lifecycle classification is session policy per the drawer glossary; a half-adopted type is the dual-source-of-truth pattern itself. Classifier gets new unit tests; existing consumer tests must pass unmodified as the neutrality proof.
- **`CustomizationStore` is one ticket in `State/`** → the store is the disk contract for `customization.json`; VMs become adapters, the 4 throwaway `CustomizationTabViewModel()` constructions call the store, `.customizationDidChangeExternally` is deleted in the same PR that removes its need.
- **Dedicated closeout ticket (audit + DMG + retro)** → exit conditions are cross-ticket invariants that can regress after their originating ticket; the audit produces recorded evidence. Local-only DMG: no version bump, no GitHub release, no download-page change.
- **Phase 17 soak gate is a phase-transition condition, not ticket work** → P16.07 completes when the DMG is installed and the retro written; the daily-driver soak (no fixed calendar) gates Phase 17 *execution* only. Phase 17 planning may proceed during the soak.

## Ticket Order

1. `P16.01 Directory restructure (drawers)`
2. `P16.02 Split FloatingPetPanel.swift`
3. `P16.03 Split SettingsWindowController.swift`
4. `P16.04 WindowKey enum`
5. `P16.05 SessionLifecycle enum + classifier`
6. `P16.06 CustomizationStore single writer`
7. `P16.07 Closeout: exit audit + dogfood DMG + retrospective`

## Ticket Files

- `ticket-01-directory-restructure.md`
- `ticket-02-split-floating-pet-panel.md`
- `ticket-03-split-settings-window-controller.md`
- `ticket-04-windowkey-enum.md`
- `ticket-05-session-lifecycle.md`
- `ticket-06-customization-store.md`
- `ticket-07-closeout-dogfood-retro.md`

## Exit Condition

All seven conditions from the product plan hold on `v3_preview`, with evidence recorded in P16.07:

1. No Swift file at `apps/menubar/Sources/` root; every file lives in one of the six layer directories; project builds via xcodegen with no code changes attributable to the moves.
2. `FloatingPetPanel.swift` and `SettingsWindowController.swift` no longer exist; contents are type-per-file extractions with unchanged signatures (access-widening excepted).
3. `grep -rn '"combined"' apps/menubar/Sources` hits only `WindowKey` parse/serialize sites and test fixtures; zero policy-site string checks; the colon-split sites are gone.
4. `SessionLifecycle` exists with a single classifier; `SessionsTabViewModel` and menubar tiering consume it.
5. Exactly one write path to `customization.json` in the app target.
6. Full existing suite green; `bun run verify` and `bun run ci:quiet` pass.
7. A local DMG is packaged, installed, and running as the daily driver.

## CI Baseline

Run `bun run ci:quiet` on `v3_preview` before P16.01 starts and record the result here. This snapshot makes per-ticket CI diffs unambiguous — an agent can tell whether a failure is pre-existing or introduced.

> Baseline recorded: 2026-07-11, `bun run ci:quiet` on `v3_preview` @ a7b7eeb9 — `CodogotchiTests.xctest`: 1015 tests, 0 failures. `** TEST SUCCEEDED **`.

## Review Rules

- Tickets must be merged in order (P16.01 → P16.07); the spine is strictly serial.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Behavior bar applies per ticket: full existing suite green; existing tests modified only where a ticket's spec explicitly sanctions it (P16.06 write-path retargeting).
- Genuine pre-existing bugs exposed by the refactor are fixed in separate commits with review-gap ledger entries — never folded into refactor commits.

## Explicit Deferrals

- Prompt/dismissal and renderer-protocol convergence — Phase 17.
- `update()` pipeline restructuring (derive/diff/apply) — Phase 18; this phase only prepares its input type (`SessionLifecycle`).
- Public release / notarization / Sparkle — Track 2. Phase 16's artifact is a local dogfood DMG only.
- Behavior changes of any kind, including "while we're in here" improvements.
- Test-tree restructuring — tests stay flat in `Tests/MenubarTests/` (locked in grill); revisit after Phase 18 at the earliest.
- Mirroring the drawer taxonomy into any non-menubar target.

## Stop Conditions

- Any suite failure that looks like a genuine pre-existing bug — stop, confirm with the developer, fix in a separate commit with a review-gap ledger entry.
- A split extraction that cannot preserve signatures without more than access-widening — stop and surface the conflict rather than improvising a shim.
- A `WindowKey` consumer where the string form turns out to be load-bearing beyond parse/serialize (e.g. persistence format ambiguity) — stop and surface.
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Phase 16 establishes the drawer taxonomy and domain types that Phases 17 and 18 build on; the retro is the checkpoint that can course-correct the foundation before the risky phases inherit it.
Trigger: Developer approval of final PR merge (architecture/process impact).
Artifact: `docs/product/retrospectives/phase-16-mechanical-consolidation-retrospective.md`

**Phase 17 execution gate (beyond ticket work):** Phase 17 execution starts only after (a) the dogfood build has served as daily driver with no unexplained regressions — no fixed calendar soak — and (b) the Phase 16 retrospective is written. Phase 17 planning may proceed in parallel during the soak.
