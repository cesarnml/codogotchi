# Phase 01 — as-shipped delta

Snapshot of where the as-shipped phase diverges from
[`phase-01.md`](phase-01.md), so Phase 02 planning reads the truth, not the
intent.

## Material divergences

### Validation window: shipped as skeleton, did not execute

The plan's Exit Condition gates each said "demonstrably true." The runbook
landed (P1.21) and the orchestrator drove P1.22 (retrospective + doc sweep)
to closeout without the 7-day live execution running. All eight exit
condition rows in
[`docs/runbooks/phase-01-validation-log.md`](../../runbooks/phase-01-validation-log.md)
are unchecked. The retrospective documents this as an explicit
developer-accepted shortfall per the plan's
"explicitly accepts a shortfall" clause.

**Implication for Phase 02:** treat the engine + Convex pipeline as
"shipped, not yet calibration-verified." The first Phase 02 task that
depends on real signal output (anything reading XP totals or hook
`state.json` content) should re-verify against live data before
trusting it.

### CLI surface: 4 planned → 6 shipped

The product plan committed to `setup`, `sync`, `status`, `loot`. The
delivery plan added `config` (P1.16) and `vacation` (P1.17) as the
primitive + sugar for the three health knobs (`weekend_decay`,
`grace_days`, `vacation_until`). Both are documented in
[`README.md`](../../../README.md) and the CLI's `USAGE` string. This was
in the delivery plan, not the product plan — the product plan under-counted.

### SoA event feed integration: consumer-side complete, producer-side upstream

P1.19 lands the consumer-side reader for `.soa/events.ndjson` and the
mapping table from SoA gate events to animation states. The
producer-side emit ticket lives in the upstream `son-of-anton` repo and
ships under its own `/soa plan → decompose → execute` cycle. When that
ticket lands and is pulled in via `/soa update`, the `reliable` states
in
[`docs/contracts/animation-state-vocabulary.md`](../../contracts/animation-state-vocabulary.md)
retroactively start firing. No codogotchi-side change is needed; the
hook reads defensively.

### IPC contract revision: used exactly once, in P1.18

P1.02 carried a one-revision allowance for the hook ticket. P1.18 used
it once, bumped `schema_version`, and the contract doc absorbed the
change. The one-revision discipline held.

## Non-divergences worth restating

- All three health knobs landed as planned with `weekend_decay: false`
  default, configurable `grace_days`, and `vacation_until` ISO date.
- `getLeaderboard` / `getProfile` reactive queries remain deferred per
  plan.
- Visible loot rendering remains deferred per plan.
- Convex Cloud production deploy and two-profile smoke landed in P1.08.

## What Phase 02 should read first

1. [`docs/contracts/animation-state-vocabulary.md`](../../contracts/animation-state-vocabulary.md) —
   the IPC the macOS app will consume.
2. [`docs/contracts/soa-event-feed.md`](../../contracts/soa-event-feed.md) —
   the optional explicit-gate stream the hook merges in.
3. [`docs/product/retrospectives/phase-01-cli-convex-plumbing-retrospective.md`](../retrospectives/phase-01-cli-convex-plumbing-retrospective.md) —
   what worked, what bit, and the validation-window followup.

_Created: 2026-05-19._
