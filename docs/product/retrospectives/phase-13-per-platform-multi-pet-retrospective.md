# Phase 13 — Per-Platform Multi-Pet & Customization — Retrospective

## Scope delivered

Eight tickets across two sessions (P13.01–07 completed 2026-06-28, P13.08 completed 2026-06-29). PRs [#131](https://github.com/cesarnml/codogotchi/pull/131)–[#138](https://github.com/cesarnml/codogotchi/pull/138) on branch stacks rooted at `main`. Delivered: schema v8 CLI slice writer with `rpg-state.json` extraction; TypeScript `CustomizationJson` Zod schema and type in `packages/contracts`; Swift `RpgStateReader` + `EXPECTED_STATE_SCHEMA_VERSION = 8`; `FloatingPetWindowPool` replacing single `floatingPetController` + `PetStateFanout`; `CustomizationJsonReader` with pool mode routing; Settings > Customization tab with per-platform mode pickers and idle-dismiss TTL picker; static Codogotchi app-icon menubar status item with monochrome toggle in Settings > General; v2.0.0 version bump in all three locations; docs sweep. `PetStateFanout` was deleted. The `perPlatform` reducer is now wired to render. No DMG cut this release (planned for v2.5 post-Phase 14/15).

## What went well

**Dependency graph as serialization contract.** Ordering P13.01 (CLI schema) → P13.02 (contracts) → P13.03 (Swift reader) before P13.04 (pool) meant every downstream ticket started with type-safe, tested foundations. The stacked PR model made the boundary crossings visible in code review: each PR's diff was scoped to exactly the layer it owned, which made subagent review prompts easy to write and findings easy to localize.

**`FloatingPetWindowPool` unit-testability.** Designing the pool as a single injectable object keyed by origin (rather than N separate controllers) meant P13.04's [red] test could stand up a pool, drive it with fake slices, and assert window spawn/dismiss behavior without AppKit involvement. This test now acts as a behavioral contract for the pool — future tickets (P14+) can stress-test pool behavior without an app build.

**`CustomizationJsonReader` injected via closure.** Using a `CustomizationReader = () -> CustomizationSnapshot` typealias for DI meant P13.05's tests could drive mode-routing logic without touching the filesystem. The same injection pattern landed cleanly in `FloatingPetWindowPool` and `LivePollingDriver`. Consistency here paid off when P13.07 needed to extend the snapshot with `menubarIconMonochrome` — no plumbing redesign required.

**Read-merge-write pattern for `customization.json`.** P13.06 and P13.07 both touched `customization.json` writes. The pattern was established in P13.06 (abort on unreadable file, preserve all existing keys) and P13.07 applied it without friction. The subagent review for P13.07 caught a correctness gap in the "persist before updating in-memory state" ordering — the pattern was right, the initial application was wrong about sequencing. Catching it pre-PR avoided a user-visible bug where the toggle would flip visually even when the write failed.

**Subagent review as a pre-PR invariant prober.** Six of seven code tickets ran a codex-cli subagent review. P13.03 (RpgStateReader) and P13.06 (Customization tab), and P13.07 (static icon + monochrome) all caught real correctness issues before the PR was opened. The adversarial prompts that named specific attack surfaces (not generic "find holes") correlated with findings that were actionable and correctly scoped. P13.04 (FloatingPetWindowPool) subagent runner returned `skipped` due to tooling availability — the reviewer falling back to a recorded skip rather than a hallucinated clean outcome was the right contract.

## Pain points

**Biome reformatting shared review artifacts caused repeated CI failures.** Running `bun run format` on the P13.07 worktree reformatted P13.05 and P13.06 ledger JSON files (collapsed multi-line `patches` arrays to single-line), producing `verify:quiet` failures on subsequent CI runs. This happened twice. Root cause: the ledger files were committed with a style that Biome's current config rejects, and `bun run format` does not scope to changed files only. **Avoidable waste** — a `.biomeignore` for review artifact directories, or writing ledger JSON in Biome's preferred single-line array style from the start, would eliminate this class of failure entirely. Consider adding `docs/product/delivery/**/reviews/**` to `.biomeignore`.

**Run-policy divergence on resume.** The delivery state persisted `ticketBoundaryMode: cook` but `orchestrator.config.json` had `gated`. On `/soa resume`, the `--baseline orchestrator` flag was required to unstick the post-red and post-verify commands. The divergence arose because the resume was invoked with `--boundary-mode cook` (user intent) while the repo config had drifted to `gated`. **Expected cost** if boundary mode is changed mid-phase — but the error message was clear and the resolution path (`--baseline orchestrator`) was fast.

**Implementation left uncommitted across session boundary.** P13.07's implementation was in the worktree as unstaged changes at the start of this session (post-red had been recorded, implementation was done but not committed). The stash-post-red-unstash sequence was needed to verify the state was sound before continuing. **Expected cost** of session interruption — but documenting the expected sequence (commit implementation before session ends, or note the interruption in state) would make recovery faster.

**`post-red` validation of worktree state.** The orchestrator's `post-red` command checks `state.json` ticket status; the worktree state.json showed `red_complete` (recorded in the prior session) while the main repo's state.json still showed `in_progress`. This caused initial confusion about whether post-red was needed. The worktree state.json is the authoritative source on resume — reading it first (rather than the main repo copy) is the right habit.

## Surprises

**`NSApp.applicationIconImage` at 18×18 works correctly as the menubar identity icon.** The ticket spec was uncertain whether the 1024pt app icon would render well at status-item scale. In practice, macOS scales the `NSApp.applicationIconImage` correctly when resized to 18×18 before assignment to `button.image`. No separate `menubar-icon` asset catalog entry was needed. The `isTemplate = true` path for monochrome mode also worked correctly via the copy — setting it on the copy (not the original) was a subtle but necessary detail that the subagent review confirmed was handled correctly.

**`GeneralTabView` autolayout emits unsatisfiable-constraint logs in tests.** The subagent review for P13.07 noted that `bun run mac:test` emits AppKit unsatisfiable-constraint logs from `SettingsWindowOpenTests` (the `GeneralTabView` laid out at a 20pt width during test). This is a pre-existing condition in the test suite (not introduced by P13.07), but it's now the first time it was formally captured. Tracked in the Advisory Observations of the P13.07 review report.

**`setMonochromeMenubarIcon` needed persist-first sequencing.** The initial implementation updated `menubarIconMonochrome = value` before the write, and the SettingsWindowController forwarded `onMonochromeChanged` unconditionally. The subagent found that a failed write (unreadable file, disk full) would leave the icon visually flipped with no persisted change. The fix — write first, update in-memory state only on success, forward the callback only on success — was a two-line change but required returning a `Bool` from the setter. This is a pattern the next time a Swift view-model writes to a config file: **persist first, propagate second**.

**Two-wire architecture for monochrome changes (pool + settings).** The initial design used only the pool's `onMonochromeChanged` callback (fires per tick when the file changes). The ticket spec also required immediate response to the Settings toggle. Adding a second wire through `SettingsWindowController.onMonochromeChanged` → `MenubarApp.applyMenubarIcon` was small but the interaction between the two paths (tick-driven vs. settings-driven) created a subtle dual-callback scenario. In practice the paths are non-concurrent (main-actor), but the dual-wire is worth noting for Phase 14 work that extends monochrome behavior.

## What we'd do differently

**Commit implementation before ending a session.** P13.07's session boundary left implementation as unstaged changes. A clean rule: never end a session with uncommitted implementation — either commit it (even as WIP) or stash with a note in the state file. The cost of session recovery is linear with the amount of uncommitted state.

**Write ledger JSON in Biome-compatible format from the start.** The `patches` array in ledger JSON was written multi-line; Biome reformats it to single-line. Since the orchestrator authors these files, the fix belongs in the orchestrator's JSON serialization step. This is an upstream SoA change, not a consumer-repo fix.

**Name the `customizationFilePath` DI parameter consistently.** Both `GeneralTabViewModel` and `CustomizationJsonReader` have a `customizationFilePath` injectable param, but the defaults differ in subtle ways (one uses `CodogotchiFolders.customizationPath()` evaluated at call site, one in the `init`). A shared `CodogotchiFolders.customizationPath()` call in both inits is the right pattern — no behavioral issue was surfaced, but consistency reduces the chance of a future DI mistake.

**Scope the retrospective trigger more precisely.** The plan says "trigger: developer approval of P13.08 PR merge" — but the retrospective is authored in P13.08 itself, before the PR is even opened. This is circular. The trigger should read "trigger: P13.08 PR opened" or the retrospective should be a post-merge step. Current practice (write in the PR, iterate if review requests changes) is fine — the documented trigger just doesn't match the actual workflow.

## Net assessment

Phase 13 achieved its stated goals. A user with two active platforms now sees two independent floating pet windows with no configuration; Settings > Customization exposes per-platform mode control and idle-dismiss TTL; all floating windows share a single RPG model from `rpg-state.json`; the menubar shows the static Codogotchi identity icon. The `PetStateFanout` and single-`floatingPetController` architecture from Phases 04–12 is fully retired. Schema v8 shipped with zero known regressions across 592 tests. The subagent review caught two correctness gaps (P13.06 unreadable-file abort, P13.07 persist-before-propagate sequencing) before PRs were opened — both would have been user-visible bugs on disk-error paths.

## Follow-up

- Add `docs/product/delivery/**/reviews/**` to `.biomeignore` (or fix orchestrator JSON serialization) to eliminate Biome-reformats-ledger-file CI failures. This affects every future phase.
- Investigate `SettingsWindowOpenTests` unsatisfiable-constraint AppKit log (pre-existing, now documented). If it starts masking real constraint failures, the root cause is `GeneralTabView` being laid out at 20pt width — test should pass a minimum width to the view.
- Phase 14 (per-thread floating pets) can branch directly from the `perPlatform`-wired foundation. The `session_id` slice key is already in place; the `perThread` reducer needs to be written and wired in `FloatingPetWindowPool.update`.
- The "persist first, propagate second" pattern from P13.07 should be applied to any future Settings writes that update both in-memory state and a file. Consider extracting a shared `ConfigFileWriter` helper to enforce this at the structural level.

---

_Created: 2026-06-29. PRs [#131](https://github.com/cesarnml/codogotchi/pull/131)–[#138](https://github.com/cesarnml/codogotchi/pull/138) open._
