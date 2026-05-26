# Phase 03: SoA-Aware Pet — Full Animation Coverage

**Delivery status:** Product plan approved 2026-05-23. Decomposition complete; tickets at [`docs/product/delivery/phase-03/`](../delivery/phase-03/).

## TL;DR

**Goal:** Make the pet visibly react to SoA delivery — running an SoA phase feels qualitatively different from running without it — by closing the gap between the v2 animation contract and what the renderer paints.

**Ships:**

- **Schema v2 bump** adding `requesting_input` and `errored` to the closed activity-state enum, end-to-end (TS contracts, hook detection, Swift renderer).
- **Codex sheet expansion** consuming rows previously unmapped: `waiting` (row 6), `requesting_input` (row 3, v2), `errored` (row 5, v2). Reviewing and pushing heuristics — already classified by the Phase 01 hook — wired into the renderer.
- **Codogotchi sheet loader** at `~/.codogotchi/pets/<pet>/spritesheet.webp` (24×9 grid, 12 fps, ~2s loop) for the 9 SoA + heuristic states not in the Codex sheet: `celebrating`, `hyped`, `focused`, `nervous`, `ascended`, `calling_for_backup`, `panicking`, `reviewing`, `pushing`.
- **`--demo` extended to all 15 states** at 0.5 s/frame default for visual sprite validation. Optional `CODOGOTCHI_DEMO_FRAME_MS` env var for tuning.
- **User-configurable pet** via `~/.codogotchi/config.json` (`{ "pet": "<name>" }`). Both loaders key off this single value. Default falls back to `maew`.
- **"Reveal pet folder" menu item** that opens `~/.codex/pets/` so users can drop a new pet in and edit config in one workflow.
- **Phase 03 validation runbook** documenting the synthetic-event recipes for rare-state verification.

**Defers:**

- Floating window / NSPanel / SpriteKit + mouse-interaction rows — **shipped in Phase 04** (see [`phase-04.md`](phase-04.md)); was deferred at Phase 03 planning time.
- HP overlays, death/ghost visuals, mood tints — Phase 05.
- Pet picker UI, catalog enumeration, multi-pet validation, displayName resolution — Phase 06.
- Schema versioning for `config.json` — deferred until the config has more than one key.
- Pet asset commissioning — handled outside the phase as an input (codogotchi spritesheet for Maew ships before Phase 03 ticket work starts).
- Distribution polish (signed installer, notarization, Sparkle, launch-at-login) — out.
- Public surface (Twitter, README GIF, landing page) — Phase 04+.

---

Phase 02 landed the menu-bar pet with the four floor states (`idle`, `implementing`, `running-tests`, `celebrating`). Phase 15 (upstream Son-of-Anton) landed the gate-event emission pipeline — `.soa/events.ndjson` is now produced during real delivery and the codogotchi hook already classifies the gate signals to states. The visible gap is the renderer: every SoA-driven state currently falls back to `idle`, so a user running a full phase delivery sees no visual change relative to baseline. Phase 03 closes that gap, with the codogotchi-owned spritesheet as the dramatic deliverable: SoA users get the payoff, non-SoA users get the Codex-row cleanup as supporting completeness.

## Phase Goal

This phase should leave the product in a state where:

- During a real SoA phase delivery, the menu-bar pet visibly changes state at every observable gate (`ticket_started`, `flow_state_entered`, `pr_review_window_opened`, `ticket_completed`, `review_clean_recorded`), verifiable via the transition log.
- All 15 contract states have been demonstrated to render correctly — naturally-observed states fired on real activity, rare states (`nervous`, `ascended`, `calling_for_backup`, `panicking`) fired via agent-simulated events appended to `.soa/events.ndjson` per the Phase 03 runbook.
- The two new v2 states (`requesting_input`, `errored`) are emitted by the hook and rendered by the menu-bar app — no enum value remains a ghost state in the contract.
- The owner can swap pets without recompiling by editing `~/.codogotchi/config.json` and restarting the app.
- `--demo` mode cycles every state at human-readable speed for sprite validation, so visual regressions on the 216 codogotchi-sheet frames are caught without orchestrating real agent activity.

## Committed Scope

The committed scope is grouped into five areas. Implementation sequencing is for the decompose phase; this section names *what* Phase 03 owns, not *how* it is built.

### Schema v2

- Bump `schema_version` from `1` to `2` in the contract, the TS contracts package, the hook binary's writer, and the Swift renderer's `EXPECTED_VERSION`.
- Add `requesting_input` and `errored` to the closed activity-state enum across all three surfaces.
- The forward-compat policy continues to apply (older payload → renderer parses best-effort; newer payload than expected → desaturated + tooltip). No policy change; only the version number moves.

### Hook v2 detection

- Hook emits `requesting_input` on Claude Code / Codex `Stop` events that indicate the agent is awaiting user response.
- Hook emits `errored` on agent response failure: rate limit, network error, or any cycle that does not complete a round-trip.
- Precedence rules unchanged: SoA gate events still win over heuristics; the two new states sit at the heuristic tier.

### Renderer v2

- Swift `ActivityState` enum expands from the current four cases to all 15 contract states. No `default:` catch-all — the switch stays exhaustive.
- The Codex sheet loader (`MaliPet` or its successor) maps the previously-unused rows: `waiting` (row 6), `requesting_input` (row 3), `errored` (row 5).
- A new codogotchi sheet loader reads `~/.codogotchi/pets/<pet>/spritesheet.webp` on the 24×9 grid spec from the contract. Same load-time invariants as the Codex sheet (grid divisibility, missing-file behavior).
- States served from the codogotchi sheet degrade to `idle` if the sheet is absent (graceful degradation matches the Phase 02 unknown-state fallback). A missing sheet is **not** a hard load failure — only a malformed grid is.
- `reviewing` and `pushing` were classified by the Phase 01 hook but rendered as `idle`. They now paint their respective rows.

### Demo mode

- `--demo` cycles all 15 states, one full loop per state, at a default of 500 ms per frame so each frame is individually inspectable.
- `CODOGOTCHI_DEMO_FRAME_MS` env var overrides the default when present (e.g., to validate motion at production speed).
- The Phase 02 fixture-driven pattern carries forward: new fixtures land for the 11 newly-rendered states, and they become durable test data.

### Pet configuration

- `~/.codogotchi/config.json` with a single key: `{ "pet": "<name>" }`.
- Both loaders (Codex sheet path, codogotchi sheet path) resolve the pet name from this file.
- File missing, malformed, or missing the `pet` key → fall back to the compiled-in default (`maew`).
- Named pet not present on disk → surface the no-pet-detected failure visual (parallel to the `state.json` missing-file path).
- A new menu item, **Reveal pet folder**, opens `~/.codex/pets/` in Finder so the owner can drop in a pet and edit config in one workflow.

## Explicit Deferrals

Each deferral below is named with the reason it is *not* in Phase 03, not just the future phase it might land in.

- **Floating window / NSPanel / SpriteKit and the mouse-interaction rows** (codex rows 1 `running-right`, 2 `running-left`, 4 `jumping`). **Shipped in Phase 04** — see [`phase-04.md`](phase-04.md). At Phase 03 planning time these rows were reserved in the contract and unmapped in the menu bar renderer until the float surface existed.
- **HP overlays, mood tints, death/ghost visuals.** Phase 05 (Social Drama). HP continues ticking silently. Phase 03 is animation-state vocabulary completion only; the HP overlay vocabulary is its own deliberate reveal.
- **Pet picker UI, catalog enumeration, multi-pet validation, displayName resolution.** Phase 06 (Catalog). The `config.json` pet knob is intentionally minimal — single string, owner-edited — so it doesn't anticipate or constrain the catalog design.
- **Schema versioning for `config.json`.** One key isn't worth the ceremony. When the config grows a second key (HP preferences, selected effects, etc.), add `schema_version` with a default-to-v1 migration.
- **Codogotchi spritesheet commissioning.** Treated as a pre-phase input. The owner ships the Maew sheet before ticket work starts; Phase 03 integrates it. If asset quality issues surface mid-phase, re-commissioning is a parallel track, not a Phase 03 deliverable.
- **Distribution polish** (signed installer, notarization, Sparkle, launch-at-login). Still out — the owner runs from Xcode / manual `.app` drag.
- **Public surface** (Twitter, README GIF, landing page). Phase 04+.
- **Tuning of state-change debounce, animation frame rates, idle thresholds.** Live-ops, ongoing.

## Roadmap Context

Phase 03 sits between Phase 02's menu-bar foundation and Phase 04's floating-window surface. Updated ladder:

1. **Phase 01 — CLI + Convex Plumbing.** Shipped.
2. **Phase 02 — macOS App Foundations: Menu bar pet.** Shipped.
3. **Phase 03 — SoA-Aware Pet: Full Animation Coverage.** This document.
4. **Phase 04 — Floating Pet + SpriteKit.** Float-on-top surface; consumes the reserved codex mouse-interaction rows.
5. **Phase 05 — Social Drama: HP UI, death, friends.**
6. **Phase 06 — Codogotchi pet catalog.**
7. **Phase 07+ — Premium tier.**

Only Phase 03 is locked by this document; later phases remain directional.

## Cross-Repo Dependency: Son-of-Anton

Phase 15 of Son-of-Anton (already landed upstream and pulled into this repo's subtree) introduced the `.soa/events.ndjson` writer. Phase 03 is the consumer-side payoff: the gate events SoA already emits become visually distinct in the menu bar. SoA reliability is a real risk surface — see the Risk Register — but no further SoA work is required for Phase 03 to ship.

As in prior phases, no code changes are made inside this repo's `.son-of-anton/` git subtree.

## Risk Register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Codogotchi spritesheet commissioning slips or returns low-quality frames; Phase 03 stalls waiting for assets | Medium | Treated as a pre-phase input. The owner commits to landing the sheet before ticket work starts. If asset quality issues surface mid-phase, re-commissioning runs as a parallel track and integration tickets gate only on the structurally-valid grid, not on subjective sprite quality. |
| SoA event-feed bugs (Phase 15 just shipped) cause missed or duplicated state transitions during the validation window | Medium | Phase 03 exit relies on the transition log being verifiable post-hoc, not real-time observation. If a gate event is missed in the wild, a synthetic event reproduces the rendering path — same recipe as rare-state validation. SoA-side bugs surface as PRs against the SoA repo, not Phase 03 blockers. |
| Schema v2 lockstep slips and a hook-v2 / renderer-v1 window appears in the wild | Low | n=1 user; the developer is the consumer and notices the desaturated + tooltip failure visual within minutes. Phase 03 ships both PRs in one closeout-stack pass. Renderer-first sequencing is documented as the n>1 default in the Phase 03 retrospective for future discipline. |
| `errored` detection becomes a rabbit hole — agent failure modes vary across Claude Code, Codex, network conditions, rate-limit responses | Medium | Treat the v2 hook detection as best-effort, not exhaustive. The contract names the conceptual trigger (cycle did not complete); the hook covers the cases that are cleanly detectable from the available stdin events. Edge cases ship as future hook patches, not Phase 03 blockers. |
| Config-file edit-and-restart workflow proves friction-heavy enough that the owner just edits source code instead — config knob becomes dead code | Low | The "Reveal pet folder" menu item lowers the friction. If the owner still bypasses config in practice, Phase 06 will redesign with a real picker — the config-file shape is small enough that the cost of revisiting is bounded. |
| Demo mode at 0.5 s/frame is so slow it's annoying for routine "does the app still launch" checks | Low | Env var override exists for tuning. Decompose may surface a separate `--demo-quick` if the slow default actively gets in the way; not pre-baked. |

## Open Strategic Questions

These are explicitly *not resolved* by Phase 03 and are flagged so they don't get forgotten:

- **What does Phase 06 inherit from Phase 03's `config.json`?** The single-key file is a deliberate minimum. Phase 06 may keep it as the file the pet picker writes to, or it may move pet selection into a richer manifest (`~/.codogotchi/catalog.json` with metadata about installed pets, last-played stats, etc.). Phase 03 commits to no answer; it just lands the smallest config that makes pet swapping work today.
- **Does the codogotchi sheet's "graceful degradation to idle" hold up when users have Codex pets that nobody made codogotchi sheets for?** Phase 03 only ships against Maew, which has both sheets. The behavior for "Codex sheet present, codogotchi sheet absent" is implemented (degrades to idle for the 9 codogotchi-owned states) but not exercised against real third-party pets. Phase 06 will surface what that experience actually feels like and whether the degraded-to-idle posture needs revisiting.
- **`errored`'s scope.** The contract names it but the hook will have to draw a line around which failure modes count. Rate limit and network error are clean cases; "user interrupted with Ctrl-C" or "tool call timed out but the model would have recovered" are murkier. Phase 03 lands the obvious cases; the long tail stays open.

## Exit Condition

Phase 03 is done when **all six** of the following are demonstrably true:

1. The menu-bar app builds, runs, and renders all 15 contract states correctly in `--demo` mode (visually verified frame-by-frame at 0.5 s/frame).
2. Pointed at real `~/.codogotchi/state.json` during an end-to-end SoA phase delivery, every naturally-occurring state — `idle`, `implementing`, `running-tests`, `reviewing`, `pushing`, `hyped`, `focused`, `waiting`, `celebrating`, `requesting_input`, `errored` — has fired at least once with the correct sprite, verified via the transition log.
3. Every rare state — `nervous`, `ascended`, `calling_for_backup`, `panicking` — has fired at least once via synthetic events appended to `.soa/events.ndjson` per the Phase 03 validation runbook, with the correct sprite verified by the owner.
4. Both v2 states (`requesting_input`, `errored`) have been observed firing from real hook detection (not just synthetic events) — proves the hook-side detection path is actually wired up, not just the renderer.
5. Pet swapping via `~/.codogotchi/config.json` works end-to-end: editing the file, restarting the app, seeing a different pet load. The "Reveal pet folder" menu item opens the right directory.
6. The forward-compat failure visuals continue to work — manually mismatched `schema_version` still surfaces the v1→v2 tooltip; missing pet still surfaces no-pet-detected.

No public-surface deliverable; no subjective game-feel criterion beyond the soul ("did running an SoA delivery actually *feel* different?").

## Retrospective

`required` — Phase 03 introduces the first schema-version bump after the contract's initial lockdown (a precedent worth documenting honestly), lands the renderer-first vs lockstep sequencing decision that will become the n>1 default, exercises the codogotchi spritesheet pipeline for the first time (asset commissioning learnings carry forward to Phase 06's catalog), and is the first phase whose soul depends on a cross-repo upstream (Son-of-Anton's gate emission). A retrospective also closes the Phase 02 plan's open strategic question about "richer pet format vs. atlas extension vs. premium-tier image generation" — Phase 03 picked the atlas-extension path with empirical results worth recording.
