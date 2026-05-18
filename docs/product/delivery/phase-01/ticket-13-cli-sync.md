# P1.13 CLI `codogotchi sync`

Size: 2 points
Type: feat
Scope: cli

## Outcome

- `codogotchi sync` orchestrates a single sync cycle:
  - Reads `~/.codogotchi/config.json` for credentials, URL, health config.
  - Calls each of the four sources in parallel, each wrapped in its own try/catch. A failed source emits `null` for its signal-set and pushes an error to a collected `errors[]`.
  - Determines `since` per source from prior `last_signal_at_by_source` (read from local cache `profile.json`, defaulting to a "first sync" sentinel that triggers the GitHub rate-limit cap).
  - POSTs the payload `{ profile_id, handle, signals: {...}, config, now, errors }` to `${convex_http_url}/sync`.
  - Writes the response (updated profile + new loot events) to `~/.codogotchi/profile.json` and appends loot events to a local loot log (cache copy).
  - Appends a one-line summary to `~/.codogotchi/sync.log` (rotated at 10MB): timestamp, per-source pass/fail, new XP delta, new loot count.
  - Exit code 0 if at least one source succeeded OR the Convex POST itself succeeded (a "no signals, just heartbeat" sync is still success). Exit code 1 only if **all four sources failed AND the POST failed**.
- Tests cover: all sources succeed, one source fails (per-source isolation), all sources fail but POST succeeds (exit 0), all-fail scenario (exit 1), log rotation at threshold.

## Red

- Write failing tests with mocked source clients (per-source success/fail toggles) and mocked HTTP.
- Commit: `test(P1.13): codogotchi sync per-source isolation [red]`.

## Green

- Implement orchestration. Use `Promise.allSettled` to run sources concurrently while preserving per-source outcomes.
- Implement log rotation (simplest: rename to `sync.log.1` when size > 10MB, truncate original; keep only the most recent rotation).

## Refactor

- Extract per-source runner if duplication emerges.
- Only refactor what this ticket touches.

## Review Focus

- Per-source isolation: confirm one failing source does not poison another. Reviewer reads the `Promise.allSettled` handling.
- `since` derivation per source from `profile.json` cache is correct; first-sync triggers cap behavior in `sources/github.ts` (P1.10).
- Exit code logic exactly matches the locked spec: 0 if any source OR the POST succeeded, 1 only if all sources failed AND POST failed.
- Log rotation works (write 11MB worth, confirm rotation happened, old file is `sync.log.1`).
- `now` is sent server-side rather than computed there (so server cannot drift from CLI's notion of time during the run).
- No partial writes to `profile.json` (write to temp, rename atomically — avoids corrupting cache mid-write).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **`runSync` injection seams.** Source clients are passed in as a `SourceReaders` quartet (`claude`, `codex`, `github`, `wakatime`) keyed by source name. `Promise.all` runs all four; each is wrapped in a try/catch inside `runOne`, so a thrown error becomes a null signal plus an entry in `errors[]`. Tests inject mock readers; the router builds production readers from config via `defaultReaders(config)`.
- **`since` derivation.** Read from `~/.codogotchi/profile.json` (`last_signal_at_by_source`) and parsed per source. Missing or invalid timestamps fall back to `null` so each engine source picks its own first-sync default (e.g. 90-day window for github + jsonl).
- **Exit code.** Exactly the locked spec: `0` if at least one source succeeded **or** the POST succeeded; `1` only when **all four sources failed AND** the POST failed. POST errors are caught (`postSucceeded = false`) and never thrown out of `runSync`.
- **Atomic cache writes.** `profile.json` uses the same `writeFile`+`rename` pattern as `config.json` so a kill mid-write can't corrupt the cache.
- **Loot log.** New loot events are appended as JSONL to `~/.codogotchi/loot.log` after a successful POST. No rotation in this ticket — loot volume is low; revisit if it ever matters.
- **Sync log rotation.** `~/.codogotchi/sync.log` rotates to `sync.log.1` when current size exceeds `DEFAULT_SYNC_LOG_LIMIT_BYTES` (10 MB). Only the most recent rotation is kept, per spec. Threshold is overridable via `SyncDeps.logSizeLimit` for tests.
- **`github_username` deferred.** The engine GitHub client requires a `username`. `CodogotchiConfig` gained an optional `github_username` field; when absent (which it is for users set up before P1.13), the default github reader returns null and the sync is a heartbeat for that source. A future ticket can derive it from `/user` lazily or extend `setup` to prompt for it. Not part of this slice.
- **JSONL paths.** Default Claude root is `${HOME}/.claude/projects`, Codex `${HOME}/.codex/sessions`. Both are overridable via `CODOGOTCHI_CLAUDE_ROOT` and `CODOGOTCHI_CODEX_ROOT` for tests and unconventional installs. `ENOENT` is treated as "no events yet" (null signal), not a failure.
- **No `record-review` follow-up.** Phase 01 PR-review-policy is `disabled` for this resume; `poll-review` auto-records `skipped`.
- **Subagent-review patch: surface engine soft errors.** Cross-model adversarial review confirmed the four core invariants hold (per-source isolation, exit-code spec, atomic profile cache writes, `since` mapping). Findings flagged two soft-failure surfaces in `default-readers.ts`: (a) `readWakatimeSignals` returns a `WakatimeSignalSet` with an `error: string | null` rather than throwing on HTTP failure, and (b) `readGithubSignals` returns `{ rateLimitHit: true, prs: [] }` instead of throwing when the GitHub API rate-limits the search call. The CLI reader now throws in both cases so they become real entries in `errors[]` rather than masquerading as "source ok with zero activity". Committed with `[subagent-review]` suffix.
- **Findings deferred:** Tmp-file leak on interrupted `writeProfileCache` (`${target}.tmp-*` left if `rename` fails after `writeFile`) and concurrent-sync race in `appendSyncLog` (second invocation can clobber the first's `sync.log.1`). Both flagged but not patched: cleanup-on-error would expand scope, and concurrent `codogotchi sync` is not a documented mode in Phase 01.
