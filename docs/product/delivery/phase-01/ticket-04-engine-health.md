# P1.04 Engine: Health (`health.ts`) — weekend + grace + vacation rules

Size: 2 points
Type: feat
Scope: engine

## Outcome

- `packages/engine/src/health.ts` exports `tickHealth(now: Date, profile: ProfileHealth, signals: RawSignals, config: HealthConfig): ProfileHealth`.
- All three degradation rules are baked into `tickHealth`:
  - **Weekend rule**: if `config.weekend_decay === false` (default) and `now` is Saturday or Sunday in the user's local timezone, return profile unchanged (no decay).
  - **Grace period**: if days-since-last-signal `< config.grace_days` (default 2), no decay.
  - **Vacation**: if `config.vacation_until` is set and `now <= vacation_until`, no decay.
- Death + revival logic: HP at 0 sets `died_at = now`, `cause = "decay"`, increments `death_count`. Activity above a threshold while `died_at != null` revives (`died_at = null`).
- HP bucket derivation: `hpBucket(hp): "thriving" | "getting_sick" | "near_death" | "ghost"` exported. Boundaries match `packages/contracts/` HP overlay enum from P1.02.
- All functions pure. `now` is always a parameter; no `Date.now()` calls.
- `bun test packages/engine/src/health.test.ts` covers: weekend skip (Sat + Sun), grace period boundary, vacation suspension (active + expired), HP decay accumulation across active days, death on HP=0, revival from activity, HP bucket transitions.

## Red

- Write failing tests covering each rule in isolation and one integration fixture chaining 10 days of synthetic time + signals.
- Run `bun test`; confirm failure.
- Commit: `test(P1.04): health tick with weekend/grace/vacation rules [red]`.

## Green

- Implement `tickHealth`, `hpBucket`, death/revival, weekend detection (use `Intl.DateTimeFormat` or Date methods with explicit timezone param — no system-tz reliance inside the function).
- Timezone is a `config.timezone: string` field (IANA name), defaulted by callers; engine takes it as input.

## Refactor

- Extract weekend-detection helper if it appears in more than one place.
- Only refactor what this ticket touches.

## Review Focus

- Timezone handling: weekend determination must use an explicit IANA timezone, not Node default. Reviewer constructs a test for a user in `Pacific/Auckland` whose Saturday differs from the server's day.
- Grace period boundary: is the grace window inclusive or exclusive at exactly `grace_days` days idle? Document the choice in the test name.
- Vacation expiration: when `vacation_until` is in the past, behavior reverts to normal decay (no permanent suspension after a missed `vacation off`).
- Revival from death does not retroactively restore lost HP; it resets to a documented starting value.
- HP bucket boundaries align with `packages/contracts/` enum — no off-by-one between this module's buckets and the contract.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.
