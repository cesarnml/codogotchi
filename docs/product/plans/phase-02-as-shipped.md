# Phase 02 — as-shipped delta

Snapshot of where the as-shipped phase diverges from
[`phase-02.md`](phase-02.md), so Phase 03 planning reads the truth,
not the intent.

## Material divergences

### `bun run ci` is no longer TS-only

The Phase 02 plan's `Grill-Me decisions locked` block named this
explicitly:

> **Toolchain seam.** Root `package.json` gains exactly two Swift
> scripts: `mac:build` and `mac:test`, both shelling out to
> `xcodebuild`. `bun run ci` stays TS-only — Swift verify is a
> manual step the owner runs locally and pastes into PR bodies.

The implementation diverged during the P2.04 → P2.05 window. The
orchestrator's `post-red` step runs `bun run ci`; with `ci` as
biome + cspell only, Swift compile failures in `[red]` commits were
invisible and `post-red` silently accepted broken Swift tests. The
fix landed in commit
[`27159b6 chore(ci): include mac:test in ci so Swift red commits gate orchestrator post-red`](https://github.com/cesarnml/codogotchi/commit/27159b6),
which changes:

```json
"ci": "bun run verify && bun run spellcheck && bun run mac:test",
"ci:quiet": "bun run verify:quiet && bun run spellcheck && bun run mac:test"
```

**What still matches the plan:** `apps/**` remains excluded from
biome and from cspell's non-md scan. The Swift surface does not
enter biome / cspell — only `mac:test` crosses the TS/Swift boundary.

**What changed:** `bun run ci` now invokes `xcodebuild test`. A
machine without Xcode (or with the wrong selected Xcode developer
dir) will fail `bun run ci` cleanly rather than silently passing.
The owner-attested Swift PR-body paste step is now belt-and-suspenders
rather than load-bearing.

**Implication for Phase 03:** treat `bun run ci` as already
Xcode-dependent on this repo. The Phase 03 floating-window +
SpriteKit surface should be added to the same `mac:test` scheme
(or a sibling scheme also chained from `ci`) rather than landing as
a second un-gated Swift surface. The "do we need hosted-runner
Xcode CI?" question raised in the Phase 02 retrospective's follow-up
section is still open and orthogonal to this divergence — local `ci`
gates locally, but no external CI runs `mac:test` today.

### Xcode project name

The plan referenced `apps/menubar/` with the `.xcodeproj` Xcode-native;
the as-shipped name is `Menubar.xcodeproj` (not `Codogotchi.xcodeproj`
or `MenubarPet.xcodeproj`). The plan did not lock a project name, so
this is not a divergence so much as a record for future readers
grepping the repo.

## Non-divergences worth recording

The following locked Phase 02 Grill-Me decisions all shipped exactly
as planned and are called out here so the next agent can trust them:

- **Hardcoded `[ActivityState: RowSpec]` table in Swift.** No
  extension of `pet.json`; no sibling `codogotchi-rows.json`.
  Pet-format extension stays reserved for Phase 06.
- **Pure 1 s polling of `~/.codogotchi/state.json`.** No
  `DispatchSource`, no `FSEvents`. Energy concerns explicitly
  deferred.
- **Continuous-loop animation policy.** 1 s per cycle, infinite,
  swap on transition. No Codex-style 3-cycle burst pattern.
- **Schema-version policy.** Accept `got ≤ expected`, refuse
  `got > expected`. The contract clause in
  [`docs/contracts/animation-state-vocabulary.md`](../../contracts/animation-state-vocabulary.md)
  landed in P2.02 before any Swift code consumed it.
- **Fixtures location.** One JSON per state at
  `apps/menubar/Fixtures/state-json/`; Mali fixtures (`pet.json` +
  `spritesheet.webp`) at `apps/menubar/Fixtures/mali/`.
- **Demo mode sandboxed path.** `CODOGOTCHI_DEMO=1` / `--demo`
  re-points the poll target to `$TMPDIR/codogotchi-demo/state.json`;
  the real `~/.codogotchi/state.json` is never touched in demo mode.
- **Transition log shape.** NDJSON per state change + hourly
  heartbeat; 10 MB cap, single-backup rotation (`.log.1`).
- **Menu surface.** Quit + Open log folder only. No preferences
  pane, no settings UI.
- **Swift learning artifacts.** Each Swift-touching ticket
  (P2.03–P2.10) landed `notes/private/phase-02-swift-notes/P2.NN-*.md`
  in the same PR as its code; P2.11 added `INDEX.md` as the
  curated reading order.

## Implication for Phase 03

The pipeline-and-policy plane of Phase 02 (polling cadence,
transition-logging shape, schema-version policy, demo-mode pattern)
is the load-bearing inheritance for Phase 03. Treat those bullets
above as the unchanged contract.

The toolchain-seam plane is the only place Phase 03 starts from a
moved baseline: `bun run ci` runs `mac:test`. Plan accordingly —
either keep the chain (and add Phase 03's Swift surface to the same
gate) or, if the chain itself needs reconsideration, do that as an
explicit Grill-Me revisit before Phase 03 decomposition rather than
another inline `chore(ci):` patch.
