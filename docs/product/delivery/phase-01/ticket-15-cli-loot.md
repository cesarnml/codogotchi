# P1.15 CLI `codogotchi loot`

Size: 2 points
Type: feat
Scope: cli

## Outcome

- `codogotchi loot` prints the full loot history from `~/.codogotchi/profile.json` (or a separate `loot.log` cache, whichever stores it — choice locked in P1.13 Rationale).
- Output: tier + name + source + timestamp + (optionally) the `score_explanation` for PR-quality drops.
- `--limit N` flag shows only the last N events (default: all).
- `--tier <tier>` flag filters to a single tier.
- Does NOT render sprite art. Text/icons only — visible loot rendering is explicitly deferred.
- Tests cover: empty loot history, populated list, `--limit` truncation, `--tier` filter, missing cache (helpful message).

## Red

- Write failing tests for output shape, flag handling, empty list.
- Commit: `test(P1.15): codogotchi loot output and flags [red]`.

## Green

- Implement reader + formatter. Reuse the formatter helper from P1.14 if extracted.

## Refactor

- Consolidate display formatter with `status` if overlap is real.
- Only refactor what this ticket touches.

## Review Focus

- No sprite rendering attempted (explicit deferral).
- Empty-state message is helpful, not a blank screen.
- `score_explanation` displayed when available — this is the human-readable trace the user uses to understand why a PR scored as it did.
- `--limit` and `--tier` work together (filter then limit, in that order).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **Source of truth: `~/.codogotchi/loot.log`** (JSONL), as locked in P1.13 Rationale. `profile.json` does not carry loot history; the log is the canonical local archive.
- **Filter-then-limit order.** `--tier` filters first, then `--limit N` slices the last N. This matches the review focus ("filter then limit, in that order") and the test exercises the composition.
- **Empty vs. missing.** A missing `loot.log` returns `missingCache: true` and the same empty-state message as an empty file. The empty-state hint points the user at `codogotchi sync`. Router prints to stdout in both cases (exit 0) — loot is not a configuration failure.
- **Per-line validation.** Reuses the same `isValidLootEvent` shape as `status` (typeof checks plus `Number.isFinite(ts)`) so a malformed JSONL line or an invalid `ts` is silently skipped rather than crashing `toISOString()`.
- **Module split.** `lootLogPath` and `lootLogExists` now live in `loot.ts` (canonical owner). The previous private `lootLogPath` in `status.ts` was kept (used by `readRecentLoot`) but is no longer re-exported, so `index.ts` `export *` from both files does not collide. Tests import `lootLogPath` from `./loot`.
- **No sprite art.** Explicit deferral honored — text + bracket-tagged tier only.
