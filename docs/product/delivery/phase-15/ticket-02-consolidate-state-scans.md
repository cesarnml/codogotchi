# P15.02 Refactor: consolidate state.d directory scans

Size: 2 points
Type: refactor
Scope: menubar
Red: skip

## Outcome

- The three separate per-tick scans of `state.d/` (per-platform state read, gate/context read, and any pruner/listing pass that runs on the poll path) are backed by a single shared directory listing produced once per tick.
- Behavior is unchanged: the per-origin state map, gate badges, and pruning results are identical to before for the same on-disk contents.
- The consolidation leaves a single seam that P15.03 extends to per-session granularity, rather than three independent scan sites.

## Red

- `Red: skip` — behavior-neutral refactor with no new externally observable behavior. The existing `StateJsonReaderTests`, `LivePollingDriverTests`, gate-reader tests, and `SlicePruner`/pool tests are the regression net; all must stay green.
- If profiling or a shared-listing helper introduces a new pure function with branching (e.g. stale-mtime filtering extracted), add a focused unit test for that helper even though the ticket is a refactor.

## Green

- Introduce one shared per-tick directory listing (names + mtimes) consumed by the state read, the gate/context resolution, and the on-poll pruning/listing path. Prefer passing the listing down rather than re-reading `contentsOfDirectory` at each site.
- Keep each consumer's filtering (stale-TTL, `.tmp-` skip, suffix checks) intact — only the raw directory enumeration is shared.

## Refactor

- This ticket *is* the refactor. Do not fold in the per-session reader change (that is P15.03) — the goal is a behavior-neutral scan consolidation that P15.03 builds on.
- No file moves; no `SOA_TARGET_VERSION`/migration change.

## Review Focus

- Confirm the refactor is genuinely behavior-neutral — same stale-TTL horizon, same `.tmp-`/dotfile skipping, same last-writer-wins grouping — and that the full existing menubar suite passes unchanged.
- Watch for a subtle ordering change: consolidating enumeration must not alter which slice wins a last-writer-wins tie (tie-break stays `updated_at`, not directory order).
- Confirm no consumer now scans a stale listing (the shared listing must be read fresh each tick, not cached across ticks).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Red: skip` refactor. The regression net is the unchanged existing suite (`StateJsonReaderTests`, `LivePollingTests`, `GateJsonReaderTests`, pool tests) — all 709 prior cases stayed green. A focused `StateDirectoryListingTests` (3 cases) was added for the new branching helper per the ticket's "add a focused unit test for a new pure function" clause. Full suite: 712 green, 0 failures.
Why this path: Introduced one `StateDirectoryListing` value (`scan(at:)` → names + mtimes, once per tick) and threaded it as an **optional** parameter (default `nil` → self-scan, byte-identical behavior when omitted) into the three per-tick poll-path consumers: `StateJsonReader.readPerPlatformDirectory`, `PerPlatformGateReader.read`, and `LivePollingDriver.newestFile` (×2). `LivePollingDriver.runTick` produces the listing once (skipped in preview mode, which reads no `state.d/`) and passes it to all four call sites. Each consumer keeps its own suffix/`.tmp-`/stale-TTL filtering and reads file contents fresh — only the raw enumeration is shared. This is the single seam P15.03 extends to per-session granularity.
Alternative considered: Also folding the injected primary `reader` seam (`StateJsonReader.readDirectory`, the global-winner status-item read) into the shared listing. Rejected: its injected closure type is `(String) -> Result`, relied on by `LivePollingTests`, so threading a listing through it would change the test-injection contract — exactly the scope creep the ticket warns against ("do not fold in the per-session reader change"). It also aggregates origin-less slices that the per-origin read drops, so it cannot be derived from the shared per-origin path. Left as its own read (2 enumerations/tick in production, down from 5).
Deferred: Consolidating the injected primary `reader` enumeration. The same two-overload optional-`listing:` pattern applied to `readPerPlatformDirectory` here could later be added to `StateJsonReader.readDirectory`, but that overload was intentionally NOT created this ticket (no `readDirectory(at:listing:)` exists) to avoid touching the injected `(String) -> Result` seam the tests rely on.
Subagent review: Advisory pass (claude-cli) returned no actionable findings. Two advisory observations were applied: a listing-branch-≡-self-scan equivalence test for `readPerPlatformDirectory` (the P15.03 seam), and a correction to the "Deferred" wording above (there is no extant `readDirectory(at:listing:)` overload). A third observation — a 1-tick pool flicker if `state.d/` is deleted mid-tick (`.success([:])` vs `.failure(.fileNotFound)`) — is an extreme edge case that closely matches the old multi-scan code's own race; left advisory for `/soa tao`.
Contract note: The ticket names "any pruner/listing pass that runs on the poll path" as a third scan to consolidate. In fact `SlicePruner.prune` runs on a **separate** `SlicePruneScheduler` (30-min timer, off the main thread via a utility queue) — it is not on the 1 Hz poll path, and sharing a poll-tick listing into a different-cadence off-thread pass would be incorrect. The pruner is therefore deliberately left untouched; the real per-tick scans consolidated are the per-origin state read, the per-origin gate/context read, and the newest gate/context resolution. Two new Swift files (`StateDirectoryListing.swift`, `StateDirectoryListingTests.swift`) required regenerating `Codogotchi.xcodeproj` via `xcodegen generate` (explicit file list, no synchronized groups) — the regenerated project is committed alongside the sources per `apps/menubar/README.md`.
