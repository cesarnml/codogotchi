# Phase 02: macOS App Foundations — Menu Bar Pet (Private)

**Delivery status:** Product plan approved. Update this line when decomposition starts (`/soa decompose`).

## TL;DR

**Goal:** Put a living Codex/Claude pet in the macOS menu bar that reacts visibly to the agent's state — sourced from `~/.codogotchi/state.json` — convincingly enough that the owner keeps it running all day.

**Ships:**

- An `NSStatusItem`-only menu bar app that renders Mali (hardcoded, loaded from `~/.codex/pets/mali/`) at status-bar size.
- Live animation of **the four floor states only**: `idle`, `implementing`, `running-tests`, `celebrating`. All other vocabulary states accepted without crash and rendered as `idle`.
- Three explicit failure visuals so pipeline problems are self-diagnosing: missing/unreadable `state.json` → desaturated + tooltip; schema mismatch → desaturated + tooltip with version delta; stale → render `idle` (no upper bound initially).
- A `--demo` mode that cycles the four floor states from canned fixtures, so Swift work proceeds without the hook running.
- A new audit log at `~/.codogotchi/state-transitions.log` (same rotation cap as `sync.log`) recording every observed state change.
- Menu bar item with only **Quit** and **Open log folder**. No preferences UI.

**Defers:**

- Floating window / `NSPanel` / SpriteKit — Phase 03.
- HP overlays, mood tints, death/ghost visuals — Phase 05 (Social Drama).
- Richer-than-floor animation states (`reviewing`, `nervous`, `waiting`, `ascended`, SoA gate visuals) — Phase 03 atlas extension.
- Pet picker / config-path pet / multi-pet support — Phase 06 (catalog).
- Preferences/settings UI — out.
- Launch-at-login, signed installer, notarization, Sparkle auto-update — out.
- Public surface (Twitter, README GIF, landing page) — Phase 04 (Public Launch).
- MCP server, friends, achievements, share cards — Phase 05+.
- macOS app reading directly from Convex — out; the app reads `state.json` only.
- Tuning of debounce, animation frame rates, idle/staleness thresholds — live-ops, ongoing.

---

Phase 01 built a trustworthy data pipeline whose only consumer today is a CLI. The product soul is the pet — a Codex/Claude character that *feels alive* because it reacts to what the agent is doing. Phase 02 puts the first pixel of that soul on screen. It is also the owner's first native Swift surface, taken deliberately small: `NSStatusItem` only, one hardcoded pet (Mali), and only the four animation states the stock Codex/Claude pet format already supports. The richer animation vocabulary, the floating window, the HP visuals, and the public surface all wait for later phases that have their own learning ramps. This phase is "agent state → menu bar pet, end to end, on the owner's actual machine, every working day."

## Phase Goal

This phase should leave the product in a state where:

- The owner has a Codex/Claude pet visible in the macOS menu bar throughout a normal working day and *keeps it running* — not turning it off out of annoyance.
- Each of the four floor states (`idle`, `implementing`, `running-tests`, `celebrating`) has visibly fired at least once during real agent activity, verifiable against `~/.codogotchi/state-transitions.log`.
- When `state.json` is missing, unparseable, or on a mismatched `schema_version`, the failure is visually self-diagnosing (desaturated icon + tooltip) — never silent.
- The Swift codebase is a credible foundation for Phase 03's floating-window + SpriteKit extension, with patterns (`state.json` polling, fixture-driven development, transition logging) that survive into Phase 03 without rework.
- The Phase 01 pipeline has been exercised end-to-end by a real consumer for the first time, with any surfaced issues patched on `main` before Phase 03 opens.

## Committed Scope

The committed scope is grouped into six areas. Implementation sequencing is for the decompose phase; this section names *what* Phase 02 owns, not *how* it is built.

### Menu bar app surface

- `NSStatusItem` only. No floating window, no panel, no dock icon.
- Renders Mali's spritesheet at status-bar size.
- Animation rates ship as defaults; tuning is live-ops, not a Phase 02 deliverable.
- Menu items: **Quit**, **Open log folder**. Nothing else — no preferences pane, no settings, no "About" beyond what Quit/Open log surface.

### Animation state vocabulary (floor only)

- Renders: `idle`, `implementing`, `running-tests`, `celebrating`.
- All other vocabulary states (HP buckets, mood overlays, SoA gates, richer activity states like `reviewing` / `nervous` / `waiting` / `ascended`) are *parsed and accepted* and *rendered as `idle`*. No crash on unknown states.
- HP is **not** visualized in Phase 02. The HP system continues ticking silently in the engine; visualization is the Phase 05 drama beat.

### IPC: reading `~/.codogotchi/state.json`

- The single source of truth for the app is `~/.codogotchi/state.json` (the contract documented in `docs/contracts/animation-state-vocabulary.md`).
- The app tolerates a missing file, unparseable JSON, and `schema_version` mismatch without crashing or busy-looping.
- Three explicit user-visible failure states:
  - **No file / unreadable** → render `idle` desaturated; tooltip: "codogotchi-hook not detected."
  - **File present, unparseable / schema mismatch** → render `idle` desaturated; tooltip names the version delta (e.g., "expected v2, got v3").
  - **File present but stale** → render `idle` (no special tell). No upper bound on staleness initially — quiet agent = idle pet is the truth. A threshold may be added later if live usage shows a real failure mode.
- The app reads `state.json` only. It does not read Convex, the hook binary, or any other file in `~/.codogotchi/`.

### Fixture-driven development path

- A `--demo` mode (or equivalent env var / launch flag) cycles the four floor states from canned fixture data so the Swift app can be developed and validated without the hook running.
- Demo mode is the path Swift correctness is established against; the app is pointed at live `state.json` only after demo-mode rendering is correct.
- The fixture set becomes durable test data carried into Phase 03.

### State-transition logging

- The menu bar app appends to `~/.codogotchi/state-transitions.log` on every observed state change (timestamp + state + source bits sufficient to answer "what did the app actually see?").
- Rotation cap matches `sync.log` (same size limit, same rollover convention).
- This log is the empirical artifact used to confirm exit condition #4 — it makes "did the four floor states fire on real activity?" answerable without watching the menu bar all day.

### Pet asset

- Mali only, loaded from `~/.codex/pets/mali/` (Codex/Claude pet format: `pet.json` + `spritesheet.webp`).
- No pet picker, no fallback pet, no format negotiation, no `pet.json` validation beyond what's needed to render Mali.
- The pet format is treated as the de facto contract for Phase 02 but is not exercised against multiple pets — that's Phase 06.

## Explicit Deferrals

Each deferral below is named with the reason it is *not* in Phase 02, not just the future phase it might land in.

- **Floating window / `NSPanel` / SpriteKit.** Phase 03 owns the floating pet and the full animation atlas; mixing it into Phase 02 inflates a deliberately-small Swift learning ramp.
- **HP overlays, death/ghost visuals, mood tints.** Phase 05 (Social Drama). HP keeps accumulating silently in Phase 02 — visualizing it is the dramatic reveal in a later phase, not a side effect of the macOS app landing.
- **Richer-than-floor animation states as distinct visuals.** Mali's spritesheet has the floor row set; faking richer states by reusing rows would bake mapping decisions into app code that should live in the pet contract. Phase 03's atlas extension is where this gets resolved with evidence.
- **Pet picker, config-file pet path, multi-pet support.** Phase 06 (catalog). Forcing pet selection into Phase 02 would also force malformed-pet failure handling — extra Swift surface that doesn't serve the phase goal.
- **Preferences/settings UI.** Out — Phase 02's only menu items are Quit and Open log folder. Every additional menu item is Swift surface that doesn't move the pet.
- **Launch-at-login, signed installer, notarization, Sparkle auto-update.** Out — Phase 02 ships as a dev build the owner runs from Xcode or a manual `.app` drag. Distribution polish lives in a later phase that has signing/notarization as its own concern.
- **Public surface** (Twitter post, README GIF, landing page, web armory). Phase 04 (Public Launch) per the Phase 01 ladder.
- **MCP server, friends, achievement badges, share cards.** Phase 05+.
- **macOS app reading directly from Convex.** Out — the app reads `state.json` only. The Convex round-trip is the CLI's job; coupling the menu bar app to Convex now would bleed network failure modes into a UI layer that's supposed to be local-only.
- **Tuning of animation frame rates, state-change debounce, staleness thresholds.** Live-ops, ongoing. Phase 02 ships defaults; tuning iterates for the life of the product.

## Roadmap Context

Phase 02 sits between the (now-shipped) Phase 01 data pipeline and the Phase 03 floating-window extension. The full ladder, repeated from Phase 01 for situational awareness:

1. **Phase 01 — CLI + Convex Plumbing.** Shipped (with the validation-window shortfall recorded in `phase-01-as-shipped-delta.md`).
2. **Phase 02 — macOS App Foundations: Menu bar pet.** This document.
3. **Phase 03 — macOS App: Floating pet + SpriteKit.** Swift learning ramp #2. Full animation atlas, HP states render.
4. **Phase 04 — Public Launch: Web Armory + Leaderboard.** First public surface.
5. **Phase 05 — Social Drama: HP UI, death, friends.**
6. **Phase 06 — Codogotchi pet catalog.**
7. **Phase 07+ — Premium tier.**

Only Phase 02 is locked by this document — later phases are directional and may be reshaped by their own planning passes.

## Cross-Repo Dependency: Son-of-Anton

Phase 02 has **no blocking dependency** on Son-of-Anton. SoA gate states arriving via `state.json` are accepted-but-rendered-as-idle, so SoA's upstream producer-side emit ticket landing (or not) does not gate Phase 02. If it lands during the phase, the additional state transitions show up in `~/.codogotchi/state-transitions.log` but remain visually idle in the menu bar. Their distinct visualization is Phase 03 atlas-extension work.

As in Phase 01, no code changes are made inside this repo's `.son-of-anton/` git subtree — that directory is read-only and overwritten by `/soa update`.

## Risk Register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Swift learning ramp outweighs the visible deliverable; phase stalls | Medium | Fixture-driven `--demo` mode means Swift correctness is established independent of the hook. The app is a useful demo even if the pipeline is broken. |
| Phase 01 pipeline issues surface during real use and block Phase 02 closeout | Medium | Empirical patches land on `main` as PRs before Phase 03 opens. Phase 03 does not start until all four floor states have observably fired on real activity. |
| `state.json` schema drifts between Phase 01 hook and Phase 02 reader | Low | Phase 01 used its one revision allowance; `schema_version` is checked and surfaces as a tooltip failure visual rather than a crash. |
| Owner ships a "technically correct, emotionally dead" pet because floor-only feels samey | Medium | Soul-first exit framing — exit condition #6 requires that the owner *kept it running*, not just that the app rendered. The transition log makes the felt reactivity empirically inspectable. |
| Distribution friction (running an unsigned dev build) discourages daily use | Low | Phase 02 explicitly defers signed installer / notarization. The owner is the only user and is comfortable with Xcode / dev builds. If friction bites, it lands in a later distribution-focused phase, not Phase 02. |

## Open Strategic Questions

These are explicitly *not resolved* by Phase 02 and are flagged so they don't get forgotten:

- ~~**Richer pet format vs. atlas extension vs. premium-tier image generation.** Mali's floor row set caps what Phase 02 can render. Phase 03 will need to decide whether the path forward is (a) extending the codogotchi-compatible pet format with more sprite rows, (b) layering programmatic effects (tints, particle overlays) on top of the stock atlas, or (c) deferring richer visuals to the premium tier (Phase 07+). Phase 02 commits to no answer; it just keeps the macOS app honest about what the floor format supports.~~ **Closed in Phase 03: atlas extension.** A new codogotchi-owned spritesheet (`codogotchi-spritesheet.webp`, 24×9 grid) serves the nine SoA-gate states alongside the existing Codex sheet. See [`docs/product/retrospectives/phase-03-soa-aware-pet-retrospective.md`](../retrospectives/phase-03-soa-aware-pet-retrospective.md).
- **State-change debounce and idle-timeout tuning.** Phase 02 ships defaults; live use will reveal whether `implementing` 90% of the working day feels alive or numb. Tuning is live-ops, but the question of whether *more states* (Phase 03) or *better timing of existing states* is the higher-leverage fix stays open.
- **Whether the menu bar app should ever surface CLI-side health** (`codogotchi sync` failures, Convex outages, GitHub rate-limit hits). Phase 02 says no — the menu bar app reads `state.json` only. This is revisited if live use shows that pipeline failures go unnoticed because they're not visible in the only surface the owner looks at all day.

## Exit Condition

Phase 02 is done when **all seven** of the following are demonstrably true:

1. The menu bar app builds and runs from a dev build on the owner's machine without crashing across a normal workday, including sleep/wake cycles.
2. In `--demo` mode, the app cycles through all four floor states with correct sprite rendering.
3. Pointed at the real `~/.codogotchi/state.json`, the app has been used by the owner across at least a few real working days (no calendar gate — "enough to observe item 4").
4. Each of the four floor states — `idle`, `implementing`, `running-tests`, `celebrating` — has fired at least once on real (non-fixture) agent activity, verified by inspecting `~/.codogotchi/state-transitions.log`.
5. All three failure visuals have been observed at least once (deliberate manual trigger acceptable): no-file desaturated, schema-mismatch desaturated, stale → idle.
6. The owner self-reports that they have *kept the app running* across those working days — i.e., not turned it off out of annoyance.
7. Any Phase 01 pipeline issues surfaced by live use have been patched on `main` before Phase 03 opens.

No 7-day calendar gate; no public-surface deliverable; no subjective game-feel criterion beyond "kept it running."

## Retrospective

`required` — Phase 02 introduces the first native Swift surface, locks the `state.json` polling + transition-logging pattern that Phase 03 inherits, exercises the animation-state-vocabulary IPC contract against a real consumer for the first time, and sets the macOS build / log / debug precedent for Phases 03+. The Phase 01 retrospective's validation-window followup also wants an honest record of what the post-merge empirical patches surfaced — Phase 02 is where that record lives.
