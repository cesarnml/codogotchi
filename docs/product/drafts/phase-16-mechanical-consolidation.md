# Phase 16 Draft — Mechanical Consolidation ("Types and Drawers")

_Drafted: 2026-07-11_
_Status: Draft input for `/soa plan` — first of the three-phase Track 4 architectural consolidation program (16 → 17 → 18)_
_Source: `/soa ideate` session over `notes/private/codogotchi-v3-polish-roadmap.md` (Track 4), `docs/product/delivery/phase-15/post-phase-15-mainline-sweep.md`, Dev Guide ch. 09 (v2 as built) and ch. 10 (the seams)_

---

## Program context (shared by phases 16–18)

v3 feature scope is **closed** (2026-07-10, v2.7.0). What remains of v3 is
Track 4 (this three-phase refactor program) followed by Track 2
(notarize + Sparkle). Program invariants, decided at ideation:

- **Behavior bar: freeze + bug fixes.** Zero intentional user-visible change.
  Full existing suite (900+ tests) green per ticket. Genuine pre-existing
  bugs exposed by the refactor are fixed in **separate commits** with
  review-gap ledger entries — consistent with the v3 "bug fixes fair game"
  policy.
- **Release cadence: dogfood release at each phase closeout** so regressions
  surface phase-by-phase, never stacked.
- **Sequencing: serial 16 → 17 → 18, then Track 2.** Track 2
  (notarize/Sparkle) starts only after Phase 18 closes; v3 ships when
  Track 2 lands.
- **No big-bang.** Every ticket independently landable and behavior-neutral.
- Phase ordering rationale: 16 is mechanical/low-risk and reduces the diff
  noise of everything after it; 17 (view layer) and 18 (pool pipeline) are
  the two risky workstreams and deliberately do **not** share a dogfood
  window.

---

## Thesis

The cheap, high-leverage moves first: make the codebase navigable and give
the domain its missing vocabulary, with near-zero behavioral risk. Every
later refactor (Phase 17's renderer convergence, Phase 18's derive/diff/apply)
gets cheaper and safer once files are grouped by layer, the god-files are
split, and `WindowKey` / `SessionLifecycle` exist as real types.

Do this phase **first** — before other refactors multiply the diff noise of
moving files later (roadmap Track 4, seams doc Seam 6).

## The problem (measured 2026-07-11 on `v3_preview`)

- **67 Swift files flat in `apps/menubar/Sources/`** (~26k lines) —
  readers, writers, view models, panels, scenes, pollers, pruners, and the
  entry point at one level, discoverable only by naming convention.
- **Two god-files:** `FloatingPetPanel.swift` (5,144 lines — both panel
  controllers, both badge views, the entire right-click prompt system, the
  Panel Size pill) and `SettingsWindowController.swift` (4,438 lines — the
  seams doc doesn't even mention this second monolith).
- **Stringly-typed window keys (Seam 1):** 101 `"combined"` literal hits
  across 11 files, plus 5 colon-split sites. Every new affordance re-derives
  the origin / origin:session / combined three-way split by string
  inspection.
- **No lifecycle type (seams case study):** the Active/Live/Archived/Pruned
  session lifecycle exists only in the dev guide, code comments, and
  `SessionsTabViewModel`'s ad-hoc bucketing. Three independent clocks
  (dismiss TTL, reader staleness, prune horizon) drive it and no single type
  names it — the "Show Pet silently does nothing" bug chain took a four-part
  hunt because of exactly this.
- **Config writers multiplying (Seam 5):** `customization.json` is written
  by the Settings tab's long-lived `CustomizationTabViewModel` plus 4
  throwaway `CustomizationTabViewModel()` constructions inside right-click
  handlers, held in sync by the `.customizationDidChangeExternally`
  notification duct tape.

## Proposed scope

1. **`Sources/` directory restructure** — file moves only, into the layers
   the dev guide already teaches: `State/` (readers, writers, pruners — the
   disk contract), `Pool/` (window pool, render keys, session policy),
   `Windows/` (panel controllers, chrome panels, prompts), `Scene/`
   (SpriteKit + effects), `Settings/` (tabs + view models), `App/` (entry
   point, menu, polling driver, config bootstrap). xcodegen globs the
   directory; imports are module-internal, so no code changes.
2. **God-file splits** — type-per-file extraction, no signature changes:
   `FloatingPetPanel.swift` into its constituent controllers, badge views,
   prompt system, and size pill; `SettingsWindowController.swift` into
   per-tab files under `Settings/`.
3. **`WindowKey` enum** — `.origin(String)`, `.session(origin:id:)`,
   `.combined` — parsed once at the boundary where render keys enter the
   pool; the string form demoted to a serialization detail (`app-state.json`
   persistence, slice filenames). Kill list: the 101 `"combined"` hits and
   5 colon-split sites, reduced to parse/serialize sites only.
4. **`SessionLifecycle` type** — Active / Live / Archived / Pruned enum plus
   a single classifier consuming the three clocks; `SessionsTabViewModel`
   bucketing and the menubar lifecycle tiering rewire to it. Phase 18's
   `derive()` consumes this type instead of raw clocks.
5. **`CustomizationStore`** — one read-merge-write + change-publication type
   owning `customization.json`; Settings VM becomes a view-facing adapter,
   the 4 throwaway VM constructions and the notification duct tape are
   replaced by the store's actual API.

## Explicitly out of scope

- Any prompt/dismissal or renderer-protocol work (Phase 17).
- Any change to `update()`'s pipeline structure (Phase 18).
- Behavior changes of any kind (see program behavior bar).

## Success criteria (draft — to be firmed in `/soa plan`)

- `grep -rn '"combined"' apps/menubar/Sources` hits only WindowKey
  parse/serialize sites (and test fixtures); zero policy-site string checks.
- No Swift file in `Sources/` root; no file > ~1,500 lines (target, not
  dogma — the two god-files are the point).
- One write path to `customization.json` in the app target.
- Full existing test suite green; `bun run verify` + `bun run ci:quiet` pass;
  dogfood release cut at closeout.

## Open questions for `/soa plan`

- Exact drawer taxonomy for edge files (e.g. `RPGHUDPanel` — `Windows/` or
  `Scene/`? `PlatformAttribution` — `State/` or `Pool/`?).
- Does `project.yml` need recursive-glob changes, or do existing globs match
  subdirectories already?
- Should `Tests/MenubarTests` mirror the new directory layout in the same
  phase, or stay flat?
- Ticket ordering: restructure-then-split vs. split-then-restructure for the
  two god-files (splitting first may produce cleaner per-drawer moves).
- Does `WindowKey` land before or after the directory restructure? (Both
  orderings are safe; pick the one that minimizes rebase pain across the
  ticket stack.)

> Next step: `/soa plan docs/product/drafts/phase-16-mechanical-consolidation.md`
