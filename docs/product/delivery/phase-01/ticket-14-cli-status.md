# P1.14 CLI `codogotchi status`

Size: 2 points
Type: feat
Scope: cli

## Outcome

- `codogotchi status` reads `~/.codogotchi/profile.json` (cache, populated only by `sync`) and `~/.codogotchi/state.json` (current animation state, populated by hook — may not exist yet pre-P1.18) and prints a clean human-readable summary:
  - Handle + stage
  - Total XP and per-source XP breakdown
  - Current HP (number + bucket — `thriving` / `getting_sick` / `near_death` / `ghost`)
  - Death status if `died_at` is set
  - Last 5 loot events
  - Current animation state (if `state.json` present): activity + HP overlay
  - Last sync timestamp; flags if last sync was >24h ago
- Does NOT call Convex. Pure cache read. Fast.
- If `profile.json` does not exist, prints a helpful message pointing at `codogotchi setup`.
- Tests cover: full populated cache, missing `state.json` (skipped from output), stale last-sync warning, missing `profile.json` (helpful error).

## Red

- Write failing tests asserting output shape (snapshot-style or line-by-line).
- Commit: `test(P1.14): codogotchi status output [red]`.

## Green

- Implement read + format. Use a small formatter helper.
- No color libraries unless they are zero-dep (avoid heavy deps for a status command).

## Refactor

- Extract formatter if `loot` (P1.15) will share rendering.
- Only refactor what this ticket touches.

## Review Focus

- No network calls.
- Missing-file paths produce helpful messages, not stack traces.
- Numbers formatted readably (e.g. `12,345` not `12345.0000001`).
- Stale-sync warning threshold is documented (24h).
- Per-source XP breakdown matches Convex schema field names exactly so a reader can correlate.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **Pure cache read.** `runStatus` reads `~/.codogotchi/profile.json`, `state.json`, and the tail of `loot.log`. No HTTP, no Convex. Tested via tempdir.
- **Loot source.** Recent loot is the last 5 lines of `loot.log` (JSONL), reversed so the newest event prints first. Malformed lines are silently skipped — the loot log is best-effort cache and a corrupt line should not crash `status`.
- **Stale threshold.** 24h, expressed as `STALE_SYNC_THRESHOLD_MS` constant. `last sync` shows the cached `profile.updated_at` (Convex server time in ms); when the delta exceeds the threshold the line appends `(stale, >24h)`. `updated_at <= 0` renders `Last sync: never`.
- **Number formatting.** Uses `Math.round(n).toLocaleString("en-US")` — readable thousands separators, no fractional noise. Per-source XP labels are `claude/codex/github/wakatime` (display short form) but map directly to Convex schema `xp_by_source.{claude_code, codex, github, wakatime}`.
- **state.json optional.** Pre-P1.18 the hook binary doesn't write `state.json`. Missing or invalid JSON is treated as "no current activity" and that section is omitted. No stack traces.
- **No color libraries.** Plain text output, per the no-heavy-deps directive.
- **Subagent review.** Doc-only ticket would auto-skip; this ticket contains code, so subagent review runs.
