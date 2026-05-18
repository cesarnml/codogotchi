# P1.20 Ops — scheduled job + `scorePR` debug log + hook event fixtures

Size: 2 points
Type: chore
Scope: ops

## Outcome

- `scripts/install-scheduled-sync.sh` (macOS launchd flavor) generates and loads a `LaunchAgent` plist at `~/Library/LaunchAgents/com.codogotchi.sync.plist` that runs `codogotchi sync` every 15 minutes. Idempotent — re-running unloads and reloads cleanly.
- A cron variant `scripts/install-scheduled-sync-cron.sh` (for Linux or non-launchd setups) writes a crontab entry. Same cadence.
- Both owner and buddy install via the script during P1.21's validation week.
- `~/.codogotchi/scorePR.log` is written by the GitHub source (`packages/engine/src/sources/github.ts`) on every `scorePR` invocation: one JSON line per decision, including PR URL, score, breakdown of inputs, and explanation string. Append-only, rotated at 10MB like `sync.log`.
- `packages/engine/test/fixtures/hooks/{claude,codex}/` contains recorded event fixtures captured against the *current* Claude Code and Codex schemas. A script `scripts/capture-hook-fixtures.sh` documents how they were captured so they can be re-captured if upstream changes shape.
- `docs/runbooks/scheduled-sync.md` documents both install paths and how to inspect logs.

## Red

- Skip Red — this ticket is ops scripts, log wiring (one append-only-write line of code in the GitHub source), and recorded fixtures. The fixture *files* are the assertion artifact for downstream tickets; they get exercised in P1.18 / P1.19 tests when those tickets reference them.

## Green

- Author the two install scripts. Test on owner's machine; buddy tests during P1.21.
- Add the `scorePR` log writing to `sources/github.ts` (revisit P1.10's `Rationale` if it didn't already wire this).
- Capture hook fixtures via instrumented runs of Claude Code + Codex; store as JSON files in the fixtures dir.
- Write the runbook.

## Refactor

- None expected — ops scripts and fixture files.

## Review Focus

- launchd plist is correct (loads, runs on schedule, logs to a known path). Reviewer runs `launchctl list | grep codogotchi`.
- Cron variant is idempotent: re-running the script does not duplicate the crontab line.
- `scorePR` log entries are parseable (valid JSON per line) and informative (every input that drove the score is captured).
- Hook fixtures cover at least: Claude Code `PreToolUse`, `PostToolUse`, `Stop`; Codex equivalents; one PR-merge-adjacent event if reachable.
- Runbook is human-followable by the buddy without IRC support.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

### Implementation notes (P1.20)

- **`scorePR` log writing lives in the CLI reader, not the engine source.** The engine's `github.ts` already returns `score` and `scoreExplanation` for every PR. Moving the log write into the CLI's `default-readers.github` closure keeps engine source files free of filesystem I/O and reuses `getCodogotchiHome()`. The contract that this is "written by the GitHub source" still holds from the user's perspective: every GitHub sync run produces the log entry, regardless of the precise module that owns the `appendFile` call.
- **Log writes are best-effort.** A failure to append to `scorePR.log` is swallowed inside `default-readers`. Sync correctness must not regress when the disk is full or the home directory is read-only — the engine still returns the scored signals and the heartbeat sync completes.
- **Rotation mirrors `sync-log.ts`.** Same 10 MiB threshold, same `*.log.1` filename, same single-file rotation (no multi-generation history). Keeps operator mental model uniform.
- **launchd installer is idempotent.** Re-running unloads any prior agent before generating a fresh plist; the script is also the upgrade path when its content changes (e.g. interval override). `--uninstall` cleans up both the plist file and the launchctl registration.
- **Cron installer is idempotent via managed marker.** Each appended crontab line ends with `# managed-by:codogotchi-sync`. Re-runs strip prior managed lines before appending. Override schedule with `CODOGOTCHI_CRON_SCHEDULE` if the default `*/15 * * * *` is wrong for the host.
- **Fixtures are committed but redacted.** Paths and session ids are stubbed (`/redacted/...`, `0000-...`) so the fixtures stay portable across reviewer machines. The `capture-hook-fixtures.sh` recipe documents the steps for re-capturing if upstream schemas drift; it does not auto-run because hook lifecycles are driven by the agent runtimes, not by this repo.
- **`scorePR.log` is JSON-per-line.** Each line is a self-contained `JSON.stringify(entry)` so the file is `jq -c .`-compatible. Sync-log uses a space-separated text format; the divergence is deliberate — `scorePR.log` carries structured score breakdowns that need real fields, not flat strings.
