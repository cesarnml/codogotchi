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

Red first: [what test failed first — or note the refactor is covered by the existing suite]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
