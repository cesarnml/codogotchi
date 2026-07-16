# P19.01 Resolve real session identity, reuse it for the live label

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `DesiredWindow` carries a new `resolvedIdentity: WindowKey` field: for `.session` keys it equals the window's own key; for `.origin`/`.combined` keys it equals the real winning entry's key (`winnerEntry.key`/`combinedWinner.key`, already computed in `PoolDerive.derive` — not new data, just persisted) — falling back to the window's own key only when no winner entry resolves this tick (e.g. an empty `.combined` window built from `memory.previousCombinedWindow`).
- `window.sessionLabel`, `memory.resolvedSessionTitles` caching, and the `titleResolutionRequests` seam for `.origin`/`.combined` windows all resolve against `resolvedIdentity` instead of the fold key (`key`) — reusing `input.sessionLabels`/`input.knownSessionTitles`, which are already populated per real render key today (`PoolTickInput`'s `keysNeedingInput` already includes every raw per-slice key, not just fold keys).
- A folded window's label now live-tracks whichever session currently wins the fold, exactly like a `.session`-keyed window's label already does — no new label-fetching mechanism, this ticket only changes which key is used to read data that already exists.
- `derive` remains pure; still unwired beyond `PoolDerive` itself — no pool/UI wiring in this ticket.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Table-driven `PoolDerive` tests (extend `PoolDerivePushTests.swift`) proving: (1) a `.session` window's `resolvedIdentity == key`; (2) an `.origin` fold fed multiple session-keyed render keys resolves `resolvedIdentity` to the actual winning session's key, not `.origin(origin)`; (3) an `.origin` window backed by a single non-multiplexed (`"default"`-sentinel) slice resolves `resolvedIdentity == key` (the solo case — no folding happened, nothing to diverge); (4) a `.combined` fold resolves `resolvedIdentity` to the winning origin's real session key, not `.combined`; (5) the label for case (2)/(4) reads from `input.sessionLabels`/`knownSessionTitles` keyed by the real winner, and changes when the winner rotates tick-to-tick — the exact bug this ticket fixes.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P19.01): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement the smallest change that makes the failing tests pass
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Confirm `PoolTickInput.sessionLabels`/`knownSessionTitles` genuinely already contain entries for every raw per-slice `WindowKey` when session-pets is off, not just for fold keys — this ticket's entire premise depends on that data already existing (see `FloatingPetWindowPool.update()`'s `keysNeedingInput` construction). If it turns out data is missing for some case, that's a scope-expanding discovery — flag it in Rationale rather than silently reworking `LivePollingDriver`/`FloatingPetWindowPool.update()` beyond this ticket's stated size.
- `memory.resolvedSessionTitles` is currently cached under the fold key for `.origin` windows (a bug in its own right — a folded window's title cache can never actually hit since the real per-session title was never written there). Verify the fix re-keys this cache correctly and doesn't leave a second, now-dead cache entry under the old fold key.
- Verify `resolvedIdentity`'s fallback-to-own-key path (no winner entry this tick) doesn't regress any existing `.combined` transient-gap test from P18.03.
- Intentionally deferred: wiring `resolvedIdentity` into `pruneSession` or the Prune menu (P19.02/P19.03); the mode-indicator badge (P19.04).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: The new PoolDerivePushTests did not compile because DesiredWindow had no resolvedIdentity field.
Why this path: Added the identity as an additive DesiredWindow field, assigned it from the already-elected winner, and reused that key for existing label/title resolution paths.
Alternative considered: Changing WindowKey to encode the resolved identity was rejected because its rawValue serialization contract must remain stable.
Deferred: Prune targeting and menu copy remain for P19.02/P19.03; the mode badge remains for P19.04.
Contract note: No deviation from the ticket metadata contract.
