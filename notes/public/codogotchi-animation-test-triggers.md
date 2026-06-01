# Codogotchi Animation Test Trigger Words

These trigger words drive the preview-only animation override used by the shell helpers:

- `test-codogotchi-animation` / `tca <trigger>`
- `test-codogotchi-soa-animations` / `tcsa`
- `test-codogotchi-codex-animations` / `tcca`
- `test-codogotchi-lite-animations` / `tcla`

The preview path is temporary-only: `$TMPDIR/codogotchi-preview/`. It does not write to live `~/.codogotchi/state.json`, `~/.codogotchi/gate.json`, or `~/.codogotchi/state-transitions.log`.

## Single-trigger words

Canonical trigger words:

- `idle`
- `standby`
- `errored`
- `waiting_for_input`
- `implementing`
- `testing`
- `thinking`
- `reading`
- `cramming`
- `ticket_started`
- `red_tdd`
- `green_tdd`
- `adversarial_review`
- `open_pr`
- `poll_review`
- `record_review`
- `advance`
- `ticket_completed`
- `review_clean`

Accepted convenience aliases:

- `error` → `errored`
- `waiting` → `waiting_for_input`
- `code`, `coding`, `implement` → `implementing`
- `test` → `testing`
- `think` → `thinking`
- `read` → `reading`
- `cram` → `cramming`
- `started`, `ticket_start` → `ticket_started`
- `red` → `red_tdd`
- `green` → `green_tdd`
- `review`, `adv_review`, `adversarial` → `adversarial_review`
- `pr` → `open_pr`
- `poll`, `polling` → `poll_review`
- `record`, `recording` → `record_review`
- `done`, `completed`, `ticket_done` → `ticket_completed`
- `clean` → `review_clean`

## Sheet ownership

`tca` routes through the actual renderer ownership split:

- Hook/lite states use a preview `state` override.
- SoA gate states use a preview `gate` override.

That means `tca ticket_started` is intentionally testing the SoA gate path, not pretending `ticket_started` is a normal hook state.

## Cycle order

`tcsa` cycles the SoA sheet top-to-bottom in gate order:

1. `ticket_started`
2. `red_tdd`
3. `green_tdd`
4. `adversarial_review`
5. `open_pr`
6. `poll_review`
7. `review_clean`
8. `record_review`
9. `advance`
10. `ticket_completed`

`tcca` cycles the Codex activity animations in top-to-bottom row order:

1. `idle`
2. `standby`
3. `errored`
4. `implementing`
5. `thinking`

Notes:

- Codex `testing` currently reuses the same sheet row as `implementing`, so the cycle skips the duplicate animation.
- Codex mouse-interaction rows (`running_right`, `running_left`, `jumping`) are not part of the activity-state cycle.

`tcla` cycles the lite activity animations in top-to-bottom row order:

1. `idle`
2. `standby`
3. `thinking`
4. `reading`
5. `implementing`
6. `testing`
7. `cramming`
8. `errored`
9. `waiting_for_input`

Note:

- Lite rows 1 and 2 (`idle_impatient`, `idle_frustrated`) are time-based idle-escalation variants, not direct `ActivityState` values, so they are not individually triggerable through the current shell helpers.
