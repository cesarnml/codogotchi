# P1.17 CLI `codogotchi vacation`

Size: 2 points
Type: feat
Scope: cli

## Outcome

- `codogotchi vacation on [--until YYYY-MM-DD]` sets `health.vacation_until` in config. Default `--until` is 30 days from today if omitted.
- `codogotchi vacation off` clears `health.vacation_until` (sets to `null`).
- `codogotchi vacation status` prints current vacation state: "off", or "on until YYYY-MM-DD (N days remaining)".
- Sugar over `codogotchi config set health.vacation_until <iso>` — internally calls the same write path as P1.16.
- Tests cover: on without flag (default 30d), on with explicit date, off, status (both states), invalid date format refusal.

## Red

- Write failing tests for each branch.
- Commit: `test(P1.17): codogotchi vacation on/off/status [red]`.

## Green

- Implement subcommands as a thin wrapper over the config writer. Validate date input.

## Refactor

- Confirm the wrapper does not duplicate validation that lives in the config schema.
- Only refactor what this ticket touches.

## Review Focus

- "on" without `--until` defaults to 30 days, not "forever" — this mitigates the "forgot to turn it off" failure mode that motivated the date-based design.
- "status" output is human-readable and includes days remaining.
- Invalid date format (`2026-13-45`) refused with a clear message.
- No new persistence layer — writes go through the same code path P1.16 uses.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **Thin wrapper.** `vacationOn`/`vacationOff` both call `configSet({ path: "health.vacation_until", value })` — no parallel persistence layer. `vacationStatus` reads via `readConfig`. The "writes go through the same code path P1.16 uses" review focus is satisfied by construction.
- **Date input is YYYY-MM-DD only.** Stricter than `config set health.vacation_until <isoDateTime>` on purpose: the user-facing CLI takes a date, normalizes to midnight UTC (`2026-06-15T00:00:00.000Z`). `2026-13-45` and `tomorrow` are both rejected with a clear `ConfigCommandError`. The calendar-roundtrip check (`new Date().getUTCMonth() + 1` reconstruction) also rejects `2026-02-30`-style invalid-but-parseable dates.
- **`--until` default is 30 days.** Matches the review focus motivation — date-based design exists to mitigate the "forgot to turn it off" failure mode. Stored value is `now() + 30 * 86_400_000`, ISO-stringified.
- **`status` days-remaining math.** `Math.ceil((untilMs - nowMs) / DAY_MS)` rounds up, so a `vacation_until` of midnight tomorrow shows `1 day remaining` rather than `0`. Past-due dates clamp to `0`.
- **No new schema.** `health.vacation_until` already exists in the contracts schema (zod-nullable string) — this ticket adds no new fields.
- **Subagent review.** Code ticket; subagent runs.
