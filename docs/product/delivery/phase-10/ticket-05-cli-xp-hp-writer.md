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

Red first: `schema_version` check (expected 5, got 4) and v5 field absence.

Why this path: New `local-xp-writer.ts` module owns the cache + compute; `runHook` reads config and calls it, falling back to v4 when `rpg_enabled` is absent. Keeps the hook path backwards-compatible for Lite users and tests without config.

Alternative considered: Recompute XP from scratch on each tick vs incremental cursors. Chose incremental cursors (`last_read_at_claude` / `last_read_at_codex` as `since` dates) to avoid re-scanning all JSONL history on every event and to prevent double-counting. The cursor is set to `now` after each read, ensuring the next read only captures new events.

Active minutes: 1 event = 1 minute approximation. Simplest local proxy without Wakatime precision; Swift decay timer (P10.06) will consume `last_activity_at` for actual decay. The remainder (`active_minutes % 60`) carries forward between hook calls so partial heal-progress is not lost.

Half-hearts decay: `resolveHalfHearts` is called with the PREVIOUS `last_activity_at` (snapshot before update) so elapsed idle time since the last event is counted as decay rather than zeroed out by the current event's timestamp.

Deferred: Syncing any of this — out of scope. JSONL read rate-limiting (coarse interval) — left for follow-up; the `last_read_at` cursor already prevents double-counting, and test fixture confirms correctness.

Contract note: v5 fields (`level`, `level_fraction`, `half_hearts`, `last_activity_at`) are written only when `config.features.rpg_enabled === true`. Without config or with `rpg_enabled: false`, the hook writes `schema_version: 4` with no RPG fields — existing v4 readers and tests are unaffected.
