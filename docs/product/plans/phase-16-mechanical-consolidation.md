# Phase 16: Mechanical Consolidation ("Types and Drawers")

**Delivery status:** Approved and decomposed 2026-07-11 — delivery docs at `docs/product/delivery/phase-16/`. Awaiting preflight.

## TL;DR

**Goal:** Make the menubar codebase navigable and give the domain its missing vocabulary — with zero intentional user-visible change — so the two risky Track 4 phases (17: view layer, 18: pool pipeline) start from grouped-by-layer files and real types instead of a flat directory and string conventions.

**Ships:**

- `apps/menubar/Sources/` restructured into layer directories (`State/`, `Pool/`, `Windows/`, `Scene/`, `Settings/`, `App/`) — file moves only.
- `FloatingPetPanel.swift` (5,144 lines) and `SettingsWindowController.swift` (4,438 lines) split type-per-file; neither file exists afterward.
- `WindowKey` enum (`.origin` / `.session` / `.combined`) parsed once at the pool boundary; the string form demoted to a serialization detail.
- `SessionLifecycle` enum (Active / Live / Archived / Pruned) with a single classifier over the three clocks; `SessionsTabViewModel` bucketing and menubar lifecycle tiering rewired to it.
- `CustomizationStore` — one read-merge-write + change-publication owner for `customization.json`; the 4 throwaway view-model constructions and the `.customizationDidChangeExternally` notification duct tape replaced by its API.
- Local-only dogfood DMG at closeout (packaged and installed as daily driver; **no public GitHub release** — see Committed Scope).

**Defers:** All prompt/dismissal and renderer-protocol work (Phase 17); any change to `update()`'s pipeline structure (Phase 18); any public release (Track 2 ships v3); any behavior change whatsoever.

---

v3 feature scope closed 2026-07-10 at v2.7.0; what remains is the Track 4 refactor program (16 → 17 → 18) and then Track 2 (notarize + Sparkle). Phase 16 is deliberately first because it is the cheap, low-risk half of consolidation: every later refactor gets cheaper and safer once files are grouped by layer, the god-files are split, and `WindowKey` / `SessionLifecycle` exist as real types — and doing the moves first means phases 17/18 don't multiply the diff noise of moving files later. The problem is measured, not speculative: 67 Swift files flat in `Sources/` (~26k lines), two god-files totaling ~9.6k lines, 101 `"combined"` string literals across 11 files plus 5 colon-split sites, a session lifecycle that exists only in docs and ad-hoc bucketing, and 5 independent writers of `customization.json`.

## Phase Goal

This phase should leave the product in a state where:

- A developer can find any menubar source file by the layer it belongs to, without knowing its name — and no Swift file lives at `Sources/` root.
- The origin / origin:session / combined three-way split is expressed by matching on `WindowKey`, not by inspecting strings; new affordances cannot re-derive it wrong.
- The Active/Live/Archived/Pruned lifecycle is a named type with one classifier, so the next "Show Pet silently does nothing"-class bug is a match-statement read, not a four-part hunt.
- `customization.json` has exactly one write path in the app target.
- The app behaves identically to v2.7.0 — the full existing suite (900+ tests) is green, and the dogfood build survives daily-driver use with no unexplained regressions.

## Committed Scope

### Program invariants (binding on this phase)

- **Behavior bar: freeze + bug fixes.** Zero intentional user-visible change. Full existing suite green per ticket. Genuine pre-existing bugs exposed by the refactor are fixed in separate commits with review-gap ledger entries.
- **No big-bang.** Every ticket independently landable and behavior-neutral.
- **Serial program.** Phase 17 does not begin execution until this phase's exit condition (below) is met.

### Directory restructure (drawers)

- File moves only, into the layers the dev guide already teaches: `State/` (readers, writers, pruners — the disk contract), `Pool/` (window pool, render keys, session policy), `Windows/` (panel controllers, chrome panels, prompts), `Scene/` (SpriteKit + effects), `Settings/` (tabs + view models), `App/` (entry point, menu, polling driver, config bootstrap).
- Edge-file drawer assignments (e.g. `RPGHUDPanel`, `PlatformAttribution`) are decompose-level decisions.

### God-file splits

- `FloatingPetPanel.swift` → constituent panel controllers, badge views, the right-click prompt system, and the Panel Size pill, type-per-file, no signature changes.
- `SettingsWindowController.swift` → per-tab files under `Settings/`, type-per-file, no signature changes.
- ~1,500 lines per file is guidance, not a gate; the success criterion is structural (see Exit Condition).

### Domain types (vocabulary)

- **`WindowKey`** — `.origin(String)`, `.session(origin:id:)`, `.combined` — parsed once at the boundary where render keys enter the pool. Kill list: the 101 `"combined"` literal hits and 5 colon-split sites reduce to parse/serialize sites only (`app-state.json` persistence, slice filenames, test fixtures).
- **`SessionLifecycle`** — Active / Live / Archived / Pruned, plus a single classifier consuming the three clocks (dismiss TTL, reader staleness, prune horizon). `SessionsTabViewModel` bucketing and menubar lifecycle tiering rewire to it. Phase 18's `derive()` will consume this type instead of raw clocks.
- **`CustomizationStore`** — one read-merge-write + change-publication type owning `customization.json`. The Settings VM becomes a view-facing adapter; the 4 throwaway `CustomizationTabViewModel()` constructions in right-click handlers and the `.customizationDidChangeExternally` notification are replaced by the store's API.
- Scope decision (grilled): `SessionLifecycle` and `CustomizationStore` stay in this phase despite being semantic rather than mechanical — they are the "types" half of the thesis, Phase 18 needs `SessionLifecycle` as input, and the per-ticket green-suite behavior bar is the mitigation.

### Closeout release (decided in grill: local-only)

- Package a dogfood DMG via the normal packaging script and install it as the daily driver.
- **No public GitHub release and no download-page update for this phase** — behavior-neutral phases don't publish; the next public release ships with Track 2 / v3. This intentionally narrows the ideation invariant's "dogfood release at each phase closeout" to a local artifact.

## Explicit Deferrals

- **Prompt/dismissal and renderer-protocol convergence** — Phase 17's workstream; touching it here would put both risky view-layer changes in one dogfood window.
- **`update()` pipeline restructuring (derive/diff/apply)** — Phase 18's workstream; this phase only prepares its input type (`SessionLifecycle`).
- **Public release / notarization / Sparkle** — Track 2; Phase 16's artifact is a local dogfood DMG only.
- **Behavior changes of any kind** — including "while we're in here" improvements; anything user-visible found broken is a separate-commit bug fix with a ledger entry, not phase scope.
- **Test-tree restructuring beyond what the moves force** — whether `Tests/MenubarTests` mirrors the new layout is a decompose-level call, not a phase commitment.

## Exit Condition

The phase is done when all of the following are demonstrably true on `v3_preview`:

1. **Drawers:** No Swift file at `apps/menubar/Sources/` root; every file lives in one of the six layer directories, and the project builds via xcodegen with no code changes attributable to the moves.
2. **Splits (structural, not numeric):** `FloatingPetPanel.swift` and `SettingsWindowController.swift` no longer exist; their contents are type-per-file extractions with unchanged signatures.
3. **WindowKey kill list:** `grep -rn '"combined"' apps/menubar/Sources` hits only `WindowKey` parse/serialize sites and test fixtures; zero policy-site string checks; the 5 colon-split sites are gone.
4. **Lifecycle:** `SessionLifecycle` exists with a single classifier; `SessionsTabViewModel` and menubar tiering consume it.
5. **One writer:** exactly one write path to `customization.json` in the app target.
6. **Behavior bar:** full existing suite green; `bun run verify` and `bun run ci:quiet` pass.
7. **Dogfood:** a local DMG is packaged, installed, and running as the daily driver.

**Phase 17 execution gate (decided in grill):** Phase 17 execution starts only after (a) the dogfood build has served as daily driver with no unexplained regressions — no fixed calendar soak — and (b) the Phase 16 retrospective is written. Phase 17 *planning* may proceed in parallel during the soak.

## Retrospective

`required` — Phase 16 establishes the drawer taxonomy and domain types that Phases 17 and 18 build on; a retro at closeout is the checkpoint that can course-correct the foundation before the risky phases inherit it.
