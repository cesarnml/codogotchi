# Scheduled sync runbook

Codogotchi expects `codogotchi sync` to run on a 15-minute cadence so the pet's
HP and XP stay close to real activity. This runbook covers the two supported
install paths and how to inspect logs if something stops working.

## Pre-requisites

- `codogotchi` is installed and on `PATH`. Verify with `command -v codogotchi`.
- `codogotchi setup` has been run at least once. The config file at
  `~/.codogotchi/config.json` must exist before the scheduled job runs.
- For GitHub PR signals: `github_token` and `github_username` are set in the
  config. The engine soft-skips when these are absent — sync still runs.

## Install (macOS — launchd)

```bash
bash scripts/install-scheduled-sync.sh
```

What it does:

- Generates `~/Library/LaunchAgents/com.codogotchi.sync.plist` pointing at the
  installed `codogotchi` binary with `StartInterval = 900` seconds (15 min).
- Loads the agent via `launchctl load`.
- Idempotent: re-running unloads first, then reloads — safe to use as your
  upgrade path when the script content changes.

Verify:

```bash
launchctl list | grep com.codogotchi.sync   # PID is "-" between runs; that is fine
tail -f ~/Library/Logs/codogotchi/sync.out.log
```

Uninstall:

```bash
bash scripts/install-scheduled-sync.sh --uninstall
```

## Install (Linux / non-launchd — cron)

```bash
bash scripts/install-scheduled-sync-cron.sh
```

What it does:

- Appends a crontab entry of the form
  `*/15 * * * * /path/to/codogotchi sync >> ~/.codogotchi/scheduled-cron.log 2>&1 # managed-by:codogotchi-sync`
- Strips any prior managed line before appending — re-running this script
  never duplicates the entry.
- Defaults to `*/15 * * * *`. Override the schedule with
  `CODOGOTCHI_CRON_SCHEDULE='*/10 * * * *' bash …` if you want a different
  cadence.

Verify:

```bash
crontab -l | grep managed-by:codogotchi-sync
tail -f ~/.codogotchi/scheduled-cron.log
```

Uninstall:

```bash
bash scripts/install-scheduled-sync-cron.sh --uninstall
```

## What to inspect when sync is silent

`~/.codogotchi/sync.log` is the canonical structured log written by the
engine. One line per sync attempt, with per-source status and XP/loot deltas:

```text
2026-05-18T14:00:01.123Z claude=ok codex=ok github=ok wakatime=ok xp_delta=420 new_loot=1
```

A line like `github=error` means the GitHub fetch failed (rate limit, expired
token, etc.). The sync still wrote a heartbeat — the pet does not die because
one source is down.

`~/.codogotchi/scorePR.log` is the GitHub source's per-PR scoring log. One
JSON object per scored PR, captured at the moment of scoring so you can audit
why a PR ended up at the score it did:

```json
{"at":"2026-05-18T14:00:01.123Z","pr_number":42,"pr_url":"https://github.com/cesarnml/codogotchi/pull/42","title":"feat: do a thing","additions":120,"deletions":40,"review_comment_count":3,"score":18,"explanation":"…"}
```

Both files rotate at 10 MiB to `*.log.1` and re-open a fresh file.

The launchd variant additionally writes stdout/stderr to
`~/Library/Logs/codogotchi/sync.{out,err}.log`. The cron variant writes to
`~/.codogotchi/scheduled-cron.log`. Those are *unstructured* — the engine log
is the source of truth; use these only when the engine log shows no recent
write at all (which means the scheduler did not even invoke the CLI).

## When to re-capture hook fixtures

Claude Code and Codex periodically reshape their hook event JSON. The
committed fixtures under `packages/engine/test/fixtures/hooks/` should be
re-captured when the codogotchi-hook starts mis-classifying real events. Use
`scripts/capture-hook-fixtures.sh` — it documents the install / drive /
restore cycle and prints the exact paths to tee stdin to.
