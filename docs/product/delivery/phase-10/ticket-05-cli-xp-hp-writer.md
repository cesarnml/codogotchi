# P10.05 CLI — local XP + HP writer (the brain)

Size: 3 points
Type: feat
Scope: cli
Red: required

## Outcome

- On hook events (and a coarse periodic refresh if one already exists), the CLI computes the full v5 progression locally and writes it into `state.json` — with **zero cloud config required**.
- **XP:** incrementally tallies cumulative tokens across `claude` + `codex` only (Antigravity is HP-only — no token counts in its local JSONL, per P10.04 stop condition), tracking a per-source last-read position so re-runs do not double-count; computes `level` + `level_fraction` via `levelForXp`/`levelProgress`.
- **HP-heal:** derives `last_activity_at` from the most recent coding event across **all five** hooked platforms (token events for Claude/Codex/Antigravity; session/activity hook events for Cursor/VS Code), accrues active minutes against the token/event floor, and writes `half_hearts` via the engine heart model.
- A Cursor- or VS Code-only event updates `last_activity_at` (so hearts live) but contributes **no XP** (level/ring frozen).
- Cumulative token totals + last-read positions persist locally (cache file under `~/.codogotchi`), independent of any sync.

## Red

- Failing integration `vitest`: fixture transcript dirs + a hook event ⇒ `state.json` has expected `level`, `level_fraction`, `half_hearts`, `last_activity_at`; a second identical run does **not** increase XP (no double count); a cursor-origin event updates `last_activity_at` but leaves `level` unchanged; with no cloud config present the write still succeeds.
- Confirm failures; commit `test(P10.05): local xp+hp state writer [red]`.

## Green

- Wire engine (P10.01/02) + contracts (P10.03) into the existing hook/state-write path; persist token cursors for `claude` + `codex`; write v5 fields. (P10.04 delivered HP-only for Antigravity; no Antigravity JSONL reader to wire.) Smallest change to pass.

## Refactor

- Reuse the existing incremental-read mechanism (`last_signal_at_by_source`-style) rather than inventing a parallel one; keep the writer idempotent.

## Review Focus

- **No double counting** across re-runs and overlapping windows — the crux.
- Activity-vs-XP separation: all 5 platforms feed `last_activity_at`; only token sources feed XP.
- Behavior with a totally fresh profile (no cache, no activity) ⇒ full hearts, level 1, no decay.
- Confirms it never reaches for `convex_http_url`/sync.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [smallest acceptable]
Alternative considered: [recompute-from-scratch each tick vs incremental cursors]
Deferred: [syncing any of this — out of scope]
Contract note: [record any metadata deviation]
