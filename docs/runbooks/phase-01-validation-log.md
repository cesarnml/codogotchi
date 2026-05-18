# Phase 01 validation log

This file is the **execution artifact** of `docs/runbooks/phase-01-validation.md`.
The runbook is the procedure; this log is the evidence. Daily entries belong
here, signed off as the week progresses.

> Status at commit time: runbook drafted; live 7-day execution **not yet
> started**. Day-by-day evidence is appended once the validation window
> begins. The phase exit gate (P1.22 retrospective) is held until either all
> eight exit conditions are checked off below or the plan author explicitly
> accepts a shortfall in writing.

## Profile pair

| User  | profile_id                  | handle      | timezone  | scheduled sync | hook installed |
| ----- | --------------------------- | ----------- | --------- | -------------- | -------------- |
| Owner | _(filled on Day 0)_         | _(filled)_  | _(filled)_| launchd        | yes / no       |
| Buddy | _(filled on Day 0)_         | _(filled)_  | _(filled)_| launchd / cron | yes / no       |

Both `profile_id`s must differ. Confirm at Day 0.

## Day 0 baseline (kickoff)

| field           | Owner               | Buddy               |
| --------------- | ------------------- | ------------------- |
| `hp`            | _(filled)_          | _(filled)_          |
| `stage`         | _(filled)_          | _(filled)_          |
| `total_xp`      | _(filled)_          | _(filled)_          |
| `weekend_decay` | `false` (default)   | `false` (default)   |
| `grace_days`    | _(from config)_     | _(from config)_     |
| `vacation_until`| `null`              | `null`              |

Notes:

- _(none yet)_

## Daily entries

### Day 1 — _(date, weekday)_

- Owner sync evidence: _(paste `tail -10 ~/.codogotchi/sync.log`)_
- Buddy sync evidence: _(paste `tail -10 ~/.codogotchi/sync.log`)_
- `codogotchi status` outputs: _(paste both)_
- Anomalies: _(none / describe)_

### Day 2 — _(date, weekday)_

_(template repeats — fill on the day)_

### Day 3 — _(date, weekday)_

### Day 4 — _(date, weekday)_

### Day 5 — _(date, weekday — first weekend day if applicable)_

- HP weekend check (Owner): _(prior-day `hp` → today `hp`; must be unchanged with `weekend_decay: false`)_
- HP weekend check (Buddy):

### Day 6 — _(date, weekday)_

### Day 7 — _(date, weekday)_

## Exit condition check-off

| #   | Condition                                                    | Owner | Buddy | Evidence pointer                                    |
| --- | ------------------------------------------------------------ | ----- | ----- | --------------------------------------------------- |
| EC1 | 7 days crash-free scheduled sync                             | ☐     | ☐     | sync.log line counts per day                        |
| EC2 | All four sources produced ≥ 1 XP event                       | ☐     | ☐     | Convex `profile.byId` → `xp_by_source`              |
| EC3 | Two profiles, no cross-bleed                                 | ☐     | n/a   | Convex direct query, both profile snapshots         |
| EC4 | HP weekend-no-decay + grace-period verified                  | ☐     | ☐     | Day 5/6 weekend HP delta                            |
| EC5 | ≥ 1 real-signal `loot_events` row                            | ☐     | ☐     | Convex `loot_events`; cross-check `scorePR.log`     |
| EC6 | ≥ 1 stage advancement (real or seeded)                       | ☐     | ☐     | Day 0 vs Day 7 `stage` delta                        |
| EC7 | `codogotchi status` clean and accurate vs Convex             | ☐     | ☐     | Day 7 status output + Convex spot-check             |
| EC8 | Hook emitted `celebrating` on a real PR merge                | ☐     | ☐     | `state.json` snapshot post-merge                    |

Seeded events: _(list each seeded source, profile, and reason — if none, "none")_

Stop conditions fired: _(list each `STOP_CONDITION` tag with date and resolution — if none, "none")_

## End-of-week sign-off

- **Status:** _(complete / partial — see deferrals)_
- **Sign-off by:** _(name, date)_
- **Phase 01 exit decision:** _(proceed to P1.22 / extend window / amend exit conditions)_

Final snapshots (paste at end of Day 7):

- Owner `profile.json`:

  ```json
  _(paste)_
  ```

- Buddy `profile.json`:

  ```json
  _(paste)_
  ```

- Convex `profiles` table (both rows):

  ```json
  _(paste)_
  ```

- Convex `loot_events` table (all rows from the window):

  ```json
  _(paste)_
  ```

## Notes for P1.22 retrospective

_(jot anything as it happens that the retrospective should pick up:
surprises, calibration drift, scheduling friction, hook misclassifications,
schema oddities. P1.22 reads this section first.)_
