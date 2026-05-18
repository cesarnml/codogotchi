# Phase 01 validation runbook (7 days, two profiles)

Phase 01 is "done" when **all eight** exit conditions in `docs/product/plans/phase-01.md` are demonstrably true. This runbook is the operator-side procedure for verifying each one. Both Phase 01 users (owner + buddy) follow it end-to-end on their own machines. Daily findings go in `docs/runbooks/phase-01-validation-log.md`.

The runbook is intentionally concrete — every check is a command, query, or screenshot, not a feeling.

## Day 0 — Walkthrough (kickoff)

Before any day-counting begins:

1. Both users run `codogotchi setup` (P1.12) and confirm `~/.codogotchi/config.json` exists with `profile_id`, `handle`, `convex_http_url`.
2. Confirm the two `profile_id`s differ. Record the pair at the top of `phase-01-validation-log.md`.
3. Install the scheduled sync per `docs/runbooks/scheduled-sync.md`. Owner uses launchd; buddy uses launchd or cron depending on platform.
4. Verify the codogotchi hook binary is on PATH (`command -v codogotchi-hook`) and that `~/.claude/settings.json` references it (P1.18 setup wired this).
5. Manually run `codogotchi sync` once. The first call seeds `~/.codogotchi/profile.json`. Confirm `~/.codogotchi/sync.log` got a new line.
6. Capture the starting `profile.json` values (`hp`, `stage`, `total_xp`) in the log under "Day 0 baseline".
7. Note both users' `~/.codogotchi/config.json` health block (timezone, vacation_until, grace_days). Weekend behavior is tied to timezone — if a user is set to UTC but lives in PST, the weekend check fires at the wrong wall-clock days.

After Day 0 is complete and both machines are healthy, start Day 1. Days 1–7 are real calendar days.

## Daily checklist (every day, both users)

Each day's log entry should record:

- Date and weekday.
- `cat ~/.codogotchi/sync.log | tail -10` for the day's sync attempts.
- `codogotchi status` raw output (and a one-line note if anything looked off).
- For weekend days only: confirm `hp` did not decay vs. the previous day's snapshot.

Skip days are logged as **skipped — reason** rather than hidden. The goal is honest evidence, not a perfect streak.

## Exit condition verification

The runbook is keyed to the eight exit conditions. Verify in the order below; some checks depend on prior ones.

### EC1. Seven consecutive days of crash-free scheduled sync (both users)

**How to check:**

```bash
# Owner
tail -200 ~/.codogotchi/sync.log
# Count sync lines per day; expect ≥ 1 per day for 7 calendar days.
awk '{print substr($1, 1, 10)}' ~/.codogotchi/sync.log | sort -u | tail -10

# Also confirm the scheduler is firing — launchd:
launchctl list | grep com.codogotchi.sync
# Cron:
crontab -l | grep managed-by:codogotchi-sync
```

A "crash" for this purpose is the CLI exiting non-zero. Per-source errors (`github=error`) are logged but do not count as a crash; the heartbeat sync still completes.

**Pass:** Both users show ≥ 7 distinct calendar dates with at least one OK sync line.

### EC2. All four signal sources produced ≥ 1 XP event end-to-end

The four sources are: Claude Code JSONL, Codex JSONL, GitHub merged PR, Wakatime hours.

**How to check (per user):**

```bash
# Inspect last syncs' per-source status
grep -E "claude=ok|codex=ok|github=ok|wakatime=ok" ~/.codogotchi/sync.log | tail -20
```

Cross-check via Convex direct query for each profile:

```ts
// Convex dashboard → Functions → Run profile.byId
{ profile_id: "<owner-or-buddy-profile-id>" }
// Confirm `xp_by_source` has all four keys > 0.
```

If any source has 0 XP at end of week, document why (no real activity, no token configured, etc.) and seed if appropriate — see "Seeding XP" below.

**Pass:** Both users have non-zero XP in all four `xp_by_source` keys at end of Day 7.

### EC3. Two distinct profiles, no cross-profile bleed

**Convex direct query (run from the production dashboard):**

```ts
// Function: profile.list (or equivalent)
// Confirm exactly two rows; capture both ids.
const rows = await db.query("profiles").collect();
// Spot-check that an owner-only signal (e.g. claude_code XP) does not appear
// on the buddy's row and vice versa.
```

Then run the per-profile fetch twice with each id and confirm the `xp_by_source`, `total_xp`, `hp`, `stage` are independent. Paste both outputs into the log.

**Pass:** Two profiles exist with non-overlapping signal histories. Cross-bleed is zero.

### EC4. HP tick respects weekend-no-decay and grace-period config

**How to check:**

1. Identify the first weekend day in the window. From the daily snapshots of `profile.json`:

   ```bash
   # On weekend morning vs. preceding weekday evening:
   jq '.hp' ~/.codogotchi/profile.json
   ```

   `hp` must not have decreased across the weekend boundary, assuming `weekend_decay: false` in the config (default).

2. Confirm grace-period honor: if a user had no activity for `grace_days = 2` consecutive days, `hp` must not yet have decayed. The third missing-activity day is the first decay opportunity.

3. Convex direct query to confirm the server's view matches:

   ```ts
   // Function: profile.byId
   { profile_id: "..." }
   // Inspect `hp`, `last_signal_at_by_source` for staleness > grace_days.
   ```

**Pass:** At least one verified weekend cycle showed `hp` unchanged. Grace-period boundary is observable in at least one profile during the window.

### EC5. ≥ 1 loot drop in `loot_events` from a real signal

**How to check (Convex direct query):**

```ts
const events = await db.query("loot_events").collect();
// Confirm at least one row with `source` in the closed enum and `score_explanation` non-null.
```

Cross-check `~/.codogotchi/scorePR.log` to see the decisions that drove the drop. A drop with `score_explanation` matching a recent log line is concrete evidence.

**Pass:** ≥ 1 row exists from a real signal (not seeded). If only a seeded drop fired, document that and flag for retrospective.

### EC6. ≥ 1 observable stage advancement (real or seeded)

**How to check:**

- Compare `stage` in Day 0 baseline vs. Day 7 final for each profile.
- If neither user advanced naturally during the week, seed XP (see "Seeding XP") on **one** profile to demonstrate the stage-advance edge fires.

**Convex direct query for evidence:**

```ts
const profile = await db.query("profiles").filter(q => q.eq(q.field("profile_id"), "...")).first();
// Snapshot `stage` and `total_xp` at Day 0 and Day 7.
```

**Pass:** At least one of the two profiles shows `stage` strictly greater at Day 7 than at Day 0. Annotate "seeded" in the log if applicable.

### EC7. `codogotchi status` output clean, readable, accurate

**How to check:**

- Run `codogotchi status` on each user's machine.
- Cross-check the displayed `hp`, `stage`, `total_xp` against the Convex direct query for that profile.
- Spot any formatting glitches (broken table cells, missing source rows, stale `last_signal_at` from before the latest sync).

**Pass:** Both users' `status` output matches Convex truth and reads clean.

### EC8. Hook binary emits `celebrating` on a real PR merge

This is the end-to-end IPC demo — the hook binary (P1.18) reads SoA events (P1.19) or a Claude Code / Codex tool-call event that maps to a PR merge, and writes `celebrating` to `~/.codogotchi/state.json`.

**How to check:**

1. During the week, merge at least one PR on either machine (real merge — closing a stale branch counts).
2. Observe `~/.codogotchi/state.json` immediately after the merge:

   ```bash
   jq '.activity_state, .source_event' ~/.codogotchi/state.json
   ```

   Expected: `activity_state = "celebrating"`, `source_event.name` reflecting the merge event (either `ticket_completed` / `review_clean_recorded` from `.soa/events.ndjson` or a recognized Claude/Codex post-tool event).

3. If the state did not flip, inspect the hook's input. The P1.20 fixtures + `capture-hook-fixtures.sh` recipe can reproduce the path locally.

**Pass:** At least one observed `celebrating` write to `state.json` traceable to a real merge.

## Seeding XP (when real activity is insufficient)

If by Day 5 a profile is still missing one source or has not advanced a stage, seed deliberately:

1. Identify the missing source. Prefer the cheapest seed path:
   - **Claude Code / Codex**: drive a small genuine coding session, even if short.
   - **GitHub**: open and merge a trivial PR (typo fix), which exercises the merge path.
   - **Wakatime**: open the editor for a non-trivial heartbeat (often the easiest).
2. Annotate the next sync entry in the log with `seed=<source>:reason`.
3. After the next Convex sync, capture the `loot_events` row (if any) and mark `score_explanation` with a `(seeded)` suffix manually in the log. Do NOT mutate Convex rows — only the log gets the annotation.

Seeded events are valid Phase 01 exit evidence so long as they are clearly flagged. The phase is exiting on whether the **system** works, not whether the user happened to do real work that week.

## What to do if a stop condition fires

Stop conditions during the validation window:

- A scheduled sync has crashed (non-zero exit) twice in a single day, or a CLI panic on first invocation.
- A Convex production query returns inconsistent state between two reads (cross-profile bleed, vanished rows).
- The hook binary spams Claude Code logs with errors (silent skip is required, P1.18 contract).
- HP decays during a configured weekend day (weekend-no-decay violated).

Escalation path:

1. Capture the offending log lines and Convex query output into the validation log under that day's entry. Tag the entry `STOP_CONDITION`.
2. Pause the scheduled sync if the crash is hot: `bash scripts/install-scheduled-sync.sh --uninstall` (or `--uninstall` on cron variant). Resuming after the fix is the same script without `--uninstall`.
3. Hand back to the plan author with:
   - The exact failing command / query.
   - The expected vs. observed result.
   - A pointer to the relevant ticket (P1.04 health, P1.06 schema, P1.07 mutation, P1.18 hook, etc.).
4. The plan author either issues a hot-fix ticket or accepts the shortfall in writing. Either way, the log records the decision.

A stop condition does not automatically fail Phase 01 — it forces an explicit decision. The retrospective (P1.22) covers what went wrong and what to change for Phase 02.

## End-of-week sign-off

When Day 7 closes:

1. Walk the eight exit conditions in this runbook against the log entries. Check each one off (or flag explicitly).
2. Capture the final `profile.json`, the final Convex `profiles` rows, and any `loot_events` rows in the log appendix.
3. If all eight are satisfied (or explicitly accepted shortfalls are recorded), Phase 01 is complete and P1.22 can begin.
4. If unresolved gaps remain, P1.22 does not start. The plan author either extends the window or amends the exit conditions, in writing.
