# Phase 03 — SoA-Aware Pet: Full Animation Coverage

> Close the gap between the v2 animation contract and what the renderer paints. Soul: an SoA phase delivery visibly lights up the menubar pet. Eight tickets, ~16 points, three stage gates.

## Epic

Source product plan: [`docs/product/plans/phase-03-soa-aware-pet-animation-coverage.md`](../../plans/phase-03-soa-aware-pet-animation-coverage.md).

## Product contract

When this phase is complete:

- During a real SoA phase delivery, the menubar pet visibly changes state at every naturally-occurring gate (`ticket_started`, `flow_state_entered`, `pr_review_window_opened`, `ticket_completed`, `review_clean_recorded`), verifiable via `~/.codogotchi/state-transitions.log`.
- All 15 contract activity states render correctly — naturally-observed states fired on real activity; rare states (`nervous`, `ascended`, `calling_for_backup`, `panicking`) fired via synthetic events appended to `.soa/events.ndjson` per the Phase 03 validation runbook.
- Both v2 states (`requesting_input`, `errored`) are emitted by the hook and rendered by the menubar — no enum value remains a ghost state in the contract.
- The owner can swap pets via `~/.codogotchi/config.json` and a Finder "Reveal pet folder" menu item, without recompiling.
- `--demo` mode cycles every state at 0.5 s/frame so visual regressions on the 216 codogotchi-sheet frames are catchable without orchestrating real agent activity.
- The forward-compat failure visuals continue to function — manually mismatched `schema_version` surfaces the v2→v3 tooltip; missing pet surfaces the no-pet-detected visual.

## Grill-Me decisions locked

- **Codogotchi spritesheet ships in-tree.** Owner commits the commissioned 24×9 Maew sheet to `apps/menubar/Fixtures/maew/codogotchi-spritesheet.webp` as the first commit on the Phase 03 branch (pre-stack input, not a ticket). Loader tests, demo fixtures, and CI reference the in-tree fixture; the user-disk path `~/.codogotchi/pets/<pet>/spritesheet.webp` is the runtime read path.
- **Swift renderer collapsed to two tickets.** P3.03 lands enum expansion (4→15) plus Codex sheet row remap (`waiting`, `requesting_input`, `errored`). P3.04 lands the new `CodogotchiPet` loader plus renderer integration plus `EXPECTED_VERSION` bump. Three-way split rejected as artificially thin.
- **Hook detection combined.** `requesting_input` and `errored` land in one ticket (P3.02). They touch the same classify function; n=1 user means slip-protection from splitting is theoretical, not real.
- **Workstream-grouped order kept.** Pet config (P3.05) lands after Swift renderer work (P3.03, P3.04), not before. The owner does not plan to exercise pet swap until real-world QA after the phase lands, so early config provides no in-phase value.
- **Contract doc + TS contracts collapsed.** Most contract work landed in this conversation; remainder (state.json v2 example, revision policy update) ships as one PR with the TS contracts package change (P3.01).
- **Test strategy: Red covers loader logic, demo covers visuals.** No pixel-diff snapshot tests on sliced `CGImage` frames — brittle, expensive, low signal. MaliPet/CodogotchiPet Red tests assert frame counts and cell coordinates only. Visual sprite correctness verified by human eye through demo mode at 0.5 s/frame.
- **P3.08 retrospective ticket also owns scoped doc-drift sweep.** In-scope: README, contract cross-references, `start-here.md`, closing Phase 02's open strategic question on "richer pet format vs atlas extension." Out-of-scope: net-new docs, cross-phase cleanup, speculative future-phase seeding.
- **Stage gates are markers, not orchestrator stops.** The orchestrator stops at every ticket boundary regardless. Gates are observation points where exit-condition progress is judgeable.
- **Lockstep release for v2 ship.** n=1 user. Both hook v2 (P3.02) and renderer v2 (P3.04) close in the same `closeout-stack` pass. Renderer-first sequencing is documented in the Phase 03 retrospective as the n>1 default for future phases — not enforced as a Phase 03 mechanic.
- **Retrospective:** `required`. Trigger: architecture/process impact (first schema-version bump after the contract's initial lockdown, first codogotchi-owned asset path, first cross-repo soul dependency on SoA) + durable-learning risk (spritesheet commissioning learnings carry forward to Phase 06 catalog).

## Ticket Order

1. `P3.01 Schema v2 — contract doc + TS contracts package`
2. `P3.02 Hook v2 detection — requesting_input + errored`
3. `P3.03 Swift ActivityState 4→15 + Codex sheet row expansion`
4. `P3.04 CodogotchiPet loader + renderer integration + EXPECTED_VERSION bump`
5. `P3.05 Pet config + Reveal pet folder menu item`
6. `P3.06 Demo mode — extended to 15 states + CODOGOTCHI_DEMO_FRAME_MS`
7. `P3.07 Validation runbook + rare-state synthetic-event recipes`
8. `P3.08 Retrospective + scoped doc-drift sweep`

## Ticket Files

- `ticket-01-schema-v2-contract-and-ts-contracts.md`
- `ticket-02-hook-v2-detection.md`
- `ticket-03-swift-enum-and-codex-sheet-expansion.md`
- `ticket-04-codogotchi-pet-loader-and-integration.md`
- `ticket-05-pet-config-and-reveal-folder.md`
- `ticket-06-demo-mode-extended.md`
- `ticket-07-validation-runbook.md`
- `ticket-08-retrospective-and-doc-sweep.md`

## Exit Condition

All six exit conditions from the product plan are demonstrably true:

1. The menubar app builds, runs, and renders all 15 contract states correctly in `--demo` mode (visually verified frame-by-frame at 0.5 s/frame).
2. Pointed at real `~/.codogotchi/state.json` during an end-to-end SoA phase delivery, every naturally-occurring state — `idle`, `implementing`, `running-tests`, `reviewing`, `pushing`, `hyped`, `focused`, `waiting`, `celebrating`, `requesting_input`, `errored` — has fired at least once with the correct sprite, verified via the transition log.
3. Every rare state — `nervous`, `ascended`, `calling_for_backup`, `panicking` — has fired at least once via synthetic events appended to `.soa/events.ndjson` per the Phase 03 validation runbook, with the correct sprite verified by the owner.
4. Both v2 states (`requesting_input`, `errored`) have been observed firing from real hook detection (not just synthetic events).
5. Pet swapping via `~/.codogotchi/config.json` works end-to-end: editing the file, restarting the app, seeing a different pet load. "Reveal pet folder" opens the correct directory.
6. The forward-compat failure visuals continue to function — manually mismatched `schema_version` still surfaces the v2→v3 tooltip; missing pet still surfaces the no-pet-detected visual.

## Stage Gates (markers, not orchestrator stops)

- **Gate 1 (after P3.02).** Hook v2 emits the two new states. Renderer is still v1, so the menubar app surfaces the forward-compat tooltip `state.json schema_version is v2; this app supports v1. Update the menu bar app.` — this is **correct behavior** and serves as the in-the-wild proof that the forward-compat policy works as specified. Owner tolerates the tooltip for the duration of Gate 1 → Gate 2.
- **Gate 2 (after P3.04).** Renderer v2 lands. All 15 states paint from their respective sheets. The tooltip clears. **This is the soul-first milestone** — pointing the app at a live SoA delivery should now produce visibly different state transitions.
- **Gate 3 (after P3.07).** Validation runbook in place; rare states (`nervous`, `ascended`, `calling_for_backup`, `panicking`) verified via synthetic events. Product-contract exit conditions 1–4 are now empirically verifiable.

## CI Baseline

> Baseline recorded: 2026-05-24 — pass (after two pre-flight fixes on main).

Run `bun run ci:quiet` and `cd apps/menubar && xcodebuild test` on `main` before P3.01 starts; record outcome here.

Pre-flight fixes folded into the baseline commit:

- `biome.json` — Biome 2.x dropped the `files.ignore` key; folded entries into `files.includes` as negated patterns so `biome check` no longer aborts on unknown-key.
- `apps/menubar/Tests/MenubarTests/MaliPetTests.swift` — `testFramesForImplementingReturnsExpectedShape` asserted that `Frame.cgImage` width/height equaled `sheet.width/8 × sheet/9`, but a prior commit (`6762842 fix(menubar): scale pet frames for macOS menubar`) rescales frames to 22 pt at @2x. Rewrote the test to assert the documented display-size invariant (22 pt × @2x) and that the frame aspect matches the source cell aspect.
- `docs/product/delivery/phase-03/implementation-plan.md` — moved `## Stage Gates` below `## Exit Condition` so the delivery orchestrator's plan parser (`/## Ticket Files\s+([\s\S]*?)\n## Exit Condition/`) does not slurp backtick-quoted prose from Stage Gates into its ticket-file count.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Swift work is verified locally via `xcodebuild test` (per Phase 02's `mac:test` convention) — the owner pastes the result into the PR body. TS work runs through `bun run ci:quiet`.
- Subagent review policy from `orchestrator.config.json` (`skip_doc_only`) means P3.01 (mixed), P3.02, P3.03, P3.04, P3.05, P3.06 receive subagent review; P3.07, P3.08 (docs-only) skip.

## Explicit Deferrals

- **Floating window / NSPanel / SpriteKit and Codex mouse-interaction rows** (rows 1, 2, 4). Phase 04. Those rows remain reserved in the contract; the renderer does not consume them in Phase 03.
- **HP overlays, death/ghost visuals, mood tints.** Phase 05. Phase 03 is animation-state vocabulary completion only.
- **Pet picker UI, catalog enumeration, multi-pet validation, displayName resolution.** Phase 06. P3.05's `config.json` knob is intentionally minimal so it doesn't anticipate the catalog design.
- **Schema versioning for `config.json`.** Deferred until the config has more than one key.
- **Codogotchi spritesheet commissioning.** Treated as a pre-phase input. Re-commissioning of bad rows is a parallel track, not a Phase 03 ticket.
- **Pixel-diff / snapshot tests on rendered frames.** Decision Q6 — visual validation is human-eye via demo mode, not automated.
- **Distribution polish** (signed installer, notarization, Sparkle, launch-at-login). Still out.

## Stop Conditions

- Codogotchi spritesheet binary is missing or has the wrong grid dimensions when P3.04 attempts to load it — re-commission or stub before continuing; do not work around in code.
- Broken CI on `main` that cannot be resolved within the active ticket scope.
- `errored` detection surfaces complexity beyond rate-limit + network-error + incomplete round-trip — stop, narrow the contract, and consider a separate follow-up ticket rather than expanding P3.02.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Architecture/process impact (first schema-version bump after the contract's initial lockdown, first codogotchi-owned asset path, first cross-repo soul dependency on SoA) plus durable-learning risk (spritesheet commissioning learnings carry forward to Phase 06's catalog).
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-03-soa-aware-pet-retrospective.md`
