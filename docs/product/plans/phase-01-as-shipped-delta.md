# Phase 01 — as-shipped delta

Snapshot of where the as-shipped phase diverges from
[`phase-01-cli-convex-plumbing.md`](phase-01-cli-convex-plumbing.md), so Phase 02 planning reads the truth, not the
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

### Signal ingest: forward-only, cumulative XP (post-closeout)

The original plan and several delivery tickets described a **90-day
first-sync lookback** for JSONL / Wakatime and a **last-90-days OR
last-20-PRs** cap on GitHub. That shipped in the stacked PR chain but
was **revised after closeout** to match product intent: reward activity
**from codogotchi onward**, not pre-install history.

**Current behavior (source of truth for agents and Phase 02):**

- **No lookback:** when `last_signal_at_by_source` is null for a source,
  `since` is the sync instant (`now`), not `now − 90 days`.
- **Incremental windows:** later syncs read from each source’s
  `last_signal_at` forward.
- **Cumulative XP:** `syncProfile` **adds** each sync’s slice to
  `xp_by_source`; null skips; zero tokens / zero hours / empty PR list
  do not erase prior totals.
- **GitHub:** no first-sync 20-PR / 90-day cap; merged PRs are those
  at or after the forward cutoff only (`resolveGithubMergedSince` in
  `packages/engine/src/sources/github.ts`).
- **CLI:** readers return `null` when a window has no measurable activity
  (skip that source for the POST). `codogotchi setup` prompts GitHub
  **username then PAT** (both required for PR signals).

Wakatime free tier still caps API history (~7 days); forward-only avoids
*asking* for 90 days the API cannot return. Deploy Convex after changing
`syncProfile` so server and CLI agree.

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
4. [`README.md`](../../../README.md) — CLI install + **forward-only** signal
   ingest summary (kept current for operators).

_Created: 2026-05-19. Signal-ingest amendment: 2026-05-20._
