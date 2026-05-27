# Phase 02 — macOS App Foundations: Menu Bar Pet

> Put a living Codex/Claude pet in the macOS menu bar that reacts visibly to the agent's state, sourced from `~/.codogotchi/state.json`. First native Swift surface in the repo; deliberately small (`NSStatusItem`-only, four floor states, hardcoded Mali). Soul-first exit gate ("kept it running"). Eleven tickets, ~17 points.

## Epic

Source product plan: [`docs/product/plans/phase-02-menu-bar-pet-foundations.md`](../../plans/phase-02-menu-bar-pet-foundations.md).

## Product contract

When this phase is complete:

- The owner has a Codex/Claude pet (Mali, hardcoded) visible in the macOS menu bar throughout a normal working day and keeps it running.
- Each of the four floor states (`idle`, `implementing`, `running-tests`, `celebrating`) has visibly fired at least once on real agent activity, verifiable in `~/.codogotchi/state-transitions.log`.
- When `state.json` is missing, unparseable, or on a newer-than-supported `schema_version`, the failure is visually self-diagnosing (desaturated icon + tooltip) — never silent.
- The Swift codebase is a credible foundation for Phase 03's floating-window + SpriteKit extension; the `state.json` polling, transition-logging, and demo-mode patterns survive without rework.
- Any Phase 01 pipeline issues surfaced by live use have been patched on `main` as standalone PRs before Phase 03 opens.

## Grill-Me decisions locked

- **Repo layout.** New top-level `apps/menubar/` containing a committed `.xcodeproj`. Resources, Info.plist (`LSUIElement=true`), and entitlements all Xcode-native. Sibling `apps/` slots reserved for Phase 03's floating window if/when needed.
- **Toolchain seam.** Root `package.json` gains exactly two Swift scripts: `mac:build` and `mac:test`, both shelling out to `xcodebuild`. `bun run ci` stays TS-only — Swift verify is a manual step the owner runs locally and pastes into PR bodies. `apps/**` excluded from biome (`.swift` would choke it) and from cspell for non-md files; markdown under `apps/` stays indexable.
- **Mali asset format.** Hardcoded `[ActivityState: RowSpec]` table in Swift. No extension to `pet.json`, no sibling `codogotchi-rows.json`, no sprite-metadata inspection. Mali-specific, intentionally not part of any pet contract. Phase 06 (catalog) is where pet-format extension lands when it has consumers.
- **State watching.** Pure 1-second polling of `~/.codogotchi/state.json`. No `DispatchSource`, no `FSEvents`. Simplest possible thing; agent-friendly to implement; energy concerns deferred to a distribution phase that doesn't exist yet.
- **Animation policy.** Continuous loop while a state is active (1s per cycle, infinite). State transitions swap to the new state's loop on the next frame. No Codex-style 3-cycle burst pattern — diverges intentionally from Codex's one-shot trigger convention because codogotchi has continuous polling, not one-shot events.
- **Schema-version policy.** Accept `got ≤ expected`, refuse `got > expected`. The IPC contract doc at `docs/contracts/animation-state-vocabulary.md` is updated in P2.02 with the forward-compat clause before any Swift code consumes it. Two tooltips: missing/non-integer, and newer-than-expected.
- **Fixtures.** One JSON file per state at `apps/menubar/Fixtures/state-json/` (`idle.json`, `implementing.json`, `running-tests.json`, `celebrating.json`, `schema-newer.json`, `unknown-state.json`). Plus `apps/menubar/Fixtures/mali/` carries a copy of `pet.json` + `spritesheet.webp` for unit-testable asset loading.
- **Demo mode.** `CODOGOTCHI_DEMO=1` env var (or `--demo` launch flag) re-points the poll target to a sandboxed path (e.g., `$TMPDIR/codogotchi-demo/state.json`). A demo driver writes fixture content to that path on a 3-second cycle. The real `~/.codogotchi/state.json` is never touched in demo mode.
- **Transition log.** NDJSON per state change plus an hourly heartbeat, written to `~/.codogotchi/state-transitions.log`. 10MB cap, single-backup rotation (`.log.1`) — matches `sync.log`'s convention without sharing rotation code across the TS/Swift boundary.
- **Phase 01 patches.** Any pipeline bugs surfaced during live Phase 02 use land as **standalone PRs on `main`** (not Phase 02 tickets). Phase 02 stack rebased after each patch lands. Cross-linked in P2.11 retrospective.
- **Exit verification.** No automation. Owner reads `state-transitions.log`, judges, decides. P2.11 retro may paste log excerpts; no required format.
- **Swift learning artifacts.** Each Swift-touching ticket (P2.03–P2.10) lands `notes/private/phase-02-swift-notes/P2.NN-<slug>.md` in the same PR as its code, as a deliverable in that ticket's Outcome bullets. Tone: "what a TS developer needs to know to review this PR honestly," not Swift-tutorial. P2.11 lands an `INDEX.md` in that directory as a curated reading order. The canonical ticket template is not modified — the deliverable lives in normal Outcome bullets, the template's intended extension point. No PR-body section, no cross-phase precedent.
- **Retrospective.** `required`. P2.11 owns it. Trigger: architecture/process impact (first native Swift surface, locks state.json polling + transition-logging patterns Phase 03 inherits) + durable-learning risk (post-merge empirical patches need an honest record).

## Ticket Order

1. `P2.01 apps/menubar Xcode project skeleton + toolchain seam`
2. `P2.02 Contract doc — animation-state-vocabulary forward-compat clause`
3. `P2.03 Swift StateJsonReader — parse + schema policy + unknown-state fallback`
4. `P2.04 Swift MaliPet asset loader + hardcoded row-map table`
5. `P2.05 Swift MenubarRenderer — NSStatusItem + continuous-loop animation`
6. `P2.06 Demo mode — sandboxed polling target + fixture cycle driver`
7. `P2.07 Live polling — ~/.codogotchi/state.json + three failure visuals`
8. `P2.08 Transition log — NDJSON writer + heartbeat + rotation`
9. `P2.09 Menu items — Quit + Open log folder + tooltip wiring`
10. `P2.10 App lifecycle hardening — sleep/wake + run instructions`
11. `P2.11 Retrospective + doc-drift sweep + swift-notes INDEX`

## Ticket Files

- `ticket-01-repo-skeleton.md`
- `ticket-02-contract-forward-compat.md`
- `ticket-03-state-json-reader.md`
- `ticket-04-mali-pet-loader.md`
- `ticket-05-menubar-renderer.md`
- `ticket-06-demo-mode.md`
- `ticket-07-live-polling.md`
- `ticket-08-transition-log.md`
- `ticket-09-menu-items.md`
- `ticket-10-lifecycle-hardening.md`
- `ticket-11-retrospective-doc-sweep.md`

## Exit Condition

All five conditions from the product contract are demonstrably true:

1. The owner has run the menu bar app throughout a normal working day and judged "kept it running" — empirically used for a few working days (no calendar gate).
2. Each of the four floor states (`idle`, `implementing`, `running-tests`, `celebrating`) has visibly fired at least once on real agent activity, verifiable in `~/.codogotchi/state-transitions.log`.
3. The three failure visuals (missing `state.json`, unparseable `state.json`, newer-than-supported `schema_version`) have each been confirmed by deliberate trigger — desaturated icon + tooltip, never silent.
4. The Swift codebase is positioned as a credible foundation for Phase 03's floating-window + SpriteKit extension; the `state.json` polling, transition-logging, and demo-mode patterns survive without rework.
5. Any Phase 01 pipeline issues surfaced by live use have been patched on `main` as standalone PRs before Phase 03 opens; cross-linked in P2.11 retrospective.

Stage gates inside the phase:

- **After P2.06.** First visible-progress milestone — `CODOGOTCHI_DEMO=1` cycles the four floor states from fixtures, with no hook running. Agent-implementable without Phase 01 pipeline involvement at all.
- **After P2.07.** First "lives in my menu bar" milestone — app pointed at real `state.json`, soul-first usage begins. Phase 01 patch-on-main mechanic activates here if needed.
- **After P2.10.** Implementation complete. Owner uses app empirically for "a few working days" (no calendar gate). All four floor states confirmed in log; failure visuals confirmed by deliberate triggers; "kept running" judgment satisfied.
- **P2.11.** Retrospective written; phase closed; `closeout-stack` squash-merges to `main`. Phase 03 opens.

## CI Baseline

> Baseline to be recorded at P2.01 — `bun run ci:quiet` on `main` immediately before the first ticket branch is created. `apps/**` is excluded from biome and from cspell non-md scanning per the toolchain seam decision, so the TS-only CI surface is unchanged by Phase 02. Swift build/test (`bun run mac:build`, `bun run mac:test`) is a manual local step the owner runs and pastes into ticket PR bodies; it does not enter `bun run ci`.

Per-ticket CI diffs are evaluated against this baseline. Any newly introduced biome diagnostic or cspell issue blocks the ticket. Swift verification is owner-attested in the PR body, not gated by `bun run ci`.

## Review Rules

- Tickets merge in order. One PR per ticket, stacked on the previous; closed out with `bun run closeout-stack` at the end.
- Each ticket PR must pass `bun run ci:quiet` before the next ticket starts. Swift-touching tickets (P2.03–P2.10) additionally require an owner-pasted `bun run mac:build` + `bun run mac:test` result in the PR body.
- Pre-existing CI failures recorded in CI Baseline above do not block; new failures do.
- The `apps/menubar/` Xcode project is committed (`.xcodeproj`); reviewers may not delete it. Resources, `Info.plist` (`LSUIElement=true`), and entitlements stay Xcode-native.
- No extension of `pet.json` or any sibling pet-format file in this phase. The Mali row-map is a hardcoded `[ActivityState: RowSpec]` table in Swift only. Pet-format extension is reserved for Phase 06.
- No `DispatchSource` / `FSEvents` for state watching. Pure 1-second polling of `~/.codogotchi/state.json` only.
- Animation tickets (P2.05+) use the continuous-loop policy (1s per cycle, infinite, swap on transition). No Codex-style 3-cycle burst pattern.
- Schema-version policy is `got ≤ expected` (accept) / `got > expected` (refuse with tooltip). P2.02 lands the contract clause before any Swift code consumes it.
- Demo mode (P2.06+) must never touch real `~/.codogotchi/state.json`. Sandboxed path under `$TMPDIR/codogotchi-demo/`.
- Phase 01 pipeline bugs surfaced during live Phase 02 use land as **standalone PRs on `main`**, not as Phase 02 tickets. The Phase 02 stack is rebased after each lands.
- Swift-touching tickets (P2.03–P2.10) land `notes/private/phase-02-swift-notes/P2.NN-<slug>.md` in the same PR as their code, as an Outcome bullet deliverable. P2.11 lands the `INDEX.md`.

## Explicit Deferrals

Carried verbatim from the product plan, restated here so they cannot drift into a ticket:

- **Floating window + SpriteKit animation surface** → Phase 03.
- **Multi-pet catalog and pet-format extension (`codogotchi-rows.json` or similar)** → Phase 06.
- **`DispatchSource` / `FSEvents` state-file watching and energy-impact tuning** → deferred until a distribution phase that doesn't exist yet.
- **Codex-style one-shot burst animations** → intentionally diverged; continuous-loop is the lock.
- **`bun run ci` integration of Swift build/test** → manual owner step this phase; revisit only if/when a CI runner with Xcode is in scope.
- **Automated exit verification (log parsers, dashboards)** → owner reads log and judges. P2.11 retro may paste excerpts; no required format.
- **Cross-pet animation contract** → Mali-specific table only; contract emerges in Phase 06 when there are real consumers.

## Stop Conditions

- Broken `bun run ci:quiet` that cannot be resolved within the ticket scope.
- Xcode project corruption or `.xcodeproj` merge conflict that cannot be cleanly resolved (escalate before re-generating).
- `state.json` schema change required mid-phase that would alter the P2.02 contract clause (escalate; revise contract before continuing Swift work that consumes it).
- Phase 01 hook ever found to be writing a malformed `state.json` that the Swift reader cannot defensively handle without changing the contract (escalate; patch Phase 01 on `main` first).
- macOS API behavior divergence between the owner's macOS version and the deployment target that breaks `NSStatusItem` or `LSUIElement=true` semantics (escalate; do not silently raise the deployment target).
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: First native Swift surface in the repo; locks the `state.json` polling cadence, transition-logging shape, and demo-mode pattern that Phase 03's floating-window + SpriteKit surface will inherit. Post-merge empirical patches against Phase 01 during live use also need an honest record before Phase 03 opens.
Trigger: architecture/process impact + durable-learning risk
Artifact: `docs/product/retrospectives/phase-02-menubar-pet-retrospective.md`

Retrospective writing, the README/AGENTS/CLAUDE/`docs/` drift sweep, and the `notes/private/phase-02-swift-notes/INDEX.md` are executed inside P2.11 via the `soa-write-retrospective` skill at phase closeout.
