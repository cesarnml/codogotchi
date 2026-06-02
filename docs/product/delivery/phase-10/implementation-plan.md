# Phase 10 — Free RPG Tier (Local Floating Progression HUD)

> Makes Codogotchi's pet alive and legible by default — local hearts, a 1–100 level, and an XP ring driven entirely by on-device coding activity, with zero cloud setup. **This phase is v1.**

## Epic

Product plan: [`docs/product/plans/phase-10.md`](../../plans/phase-10.md). Draft: [`docs/product/drafts/phase-10-floating-progression-hud.md`](../../drafts/phase-10-floating-progression-hud.md).

## Product contract

After this phase, a clean install with no configuration shows a floating pet whose **hearts** respond to coding across all five hooked platforms (Claude, Codex, Cursor, VS Code, Antigravity), and whose **level + XP ring** progress on the three agents that write local token logs (Claude, Codex, Antigravity). Hearts decay when idle and heal when active — computed locally, no network. The pet flashes Zelda-style on each ±½-heart change and on level-up. Users can disable the HUD from a new RPG tab in Settings. No account, URL, key, or network traffic is involved.

## Grill-Me decisions locked

- **Scope split** → Local RPG only is Phase 10; sync + leaderboard + auth deferred. **Phase 10 = v1; the immediate follow-on is a notarized DMG (distribution), not sync.** No cloud plumbing is built here.
- **Loop ownership (split along "needs JSONL?")** → TS/CLI owns XP + HP-heal (hook-driven, no timer); Swift hosts the decay timer and computes decay locally from `last_activity_at`. Justified because **hearts are local-only forever** (synced data, when it exists, is level + last-active only) — there is no server-side health to keep a shared rule in sync with.
- **Contract carries finished numbers** → state.json v5 hands Swift `level`, `level_fraction`, `half_hearts`, `last_activity_at` already computed; Swift does only integer decay decrement + render. Decay constants live in `@codogotchi/contracts`.
- **Hearts = `half_hearts` 0..6** as the canonical HP unit (native to the −½/8h cadence; unambiguous flash trigger). `hp`/`hp_overlay` retained, derived, for the existing sprite-overlay path.
- **Level engine is additive** → new `levelForXp`/`levelProgress`/`LEVEL_THRESHOLDS`; `STAGE_THRESHOLDS`/`stageForXp` left untouched (still read by the dormant sync path), marked deprecated.
- **Calibration constants (provisional)** → total tokens (in+out); baseline 93M/day; `T = 68e9`; `C(L) = T × ((L−1)/99)^2.5`. Re-validated against real distribution whenever sync ships. Per-user recalibration is premium.
- **Old health model left dormant** → the per-day-decay / weekend / vacation / grace config is not used by the local HUD; fully retired when sync is rebuilt later, not now.
- **Platform boundary confirmed** → Cursor + VS Code Copilot keep tokens cloud-side → HP-only (living hearts via hooks, frozen ring). Accepted, not a gap.
- **Sanity rulings** → fresh install = full hearts, no decay until first activity; ghost revives by coding again (no revive ceremony); slept laptop catches up on wake (floored at empty); Cursor/VS Code hearts live, ring frozen.

## Ticket Order

1. `P10.01 Engine — 1–100 level curve`
2. `P10.02 Engine — local heart model`
3. `P10.03 Contracts — state.json v5, local-RPG config, HUD opt-out`
4. `P10.04 Engine — Antigravity token reader`
5. `P10.05 CLI — local XP + HP writer (the brain)`
6. `P10.06 Swift — consume v5 + local decay timer`
7. `P10.07 Swift — floating HUD render + flashes`
8. `P10.08 Swift — RPG settings tab + demo mode`
9. `P10.09 Phase retrospective + documentation sweep`

## Ticket Files

- `ticket-01-engine-level-curve.md`
- `ticket-02-engine-heart-model.md`
- `ticket-03-contracts-state-v5-config.md`
- `ticket-04-engine-antigravity-reader.md`
- `ticket-05-cli-xp-hp-writer.md`
- `ticket-06-swift-decay-timer.md`
- `ticket-07-swift-hud-render-flashes.md`
- `ticket-08-swift-rpg-settings-demo.md`
- `ticket-09-retrospective.md`

## Exit Condition

Hand someone a clean install and, within one coding session, show: a floating pet whose hearts decay when idle, heal when active, and flash Zelda-style on each ±½-heart change across whichever of the five platforms they use; and — for Claude/Codex/Antigravity users — a level number inside an XP ring that fills as they work and flashes on roll-over. A Cursor- or VS Code-only user gets living hearts and a frozen ring they can hide via **Disable RPG HUD** in the new RPG settings tab. All local, no network. The 1–100 curve uses the provisional calibrated constants; demo mode showcases the HUD. The sync/leaderboard half is cleanly absent.

## CI Baseline

> Baseline recorded: **PASS** (2026-06-03) — 377 TS tests pass (25 files), 417 Swift tests pass, 0 failures. No pre-existing CI failures.

## Review Rules

- Tickets merged in order; each ticket PR passes CI before the next starts.
- Pre-existing CI failures recorded in **CI Baseline** do not block; newly introduced failures do.
- TS tickets (01–05) and Swift tickets (06–08) each gate on their own suite (`vitest` / `swift test`); the contract bump (03) must land before any v5 reader/writer.
- Per repo policy: `bun run format` → stage → commit for any orchestrator-written artifacts; `bun run verify` / `ci:quiet` before opening each PR.

## Explicit Deferrals

- Opt-in sync, public leaderboard, production Convex cut, `/sync` auth (App Attest + per-install identity + rate-limit + validation) — deferred well past v1; not "Phase 11 next."
- Notarized DMG / distribution hardening — the real next effort, tracked separately.
- Sick-idle / health-tint sprite art — later art phase.
- Loot, GitHub PR XP, WakaTime XP, premium sprite sheets, per-user curve recalibration, hours-based XP for Cursor/VS Code — paid Alive tier.
- Full removal of the dormant per-day health model — done when sync is rebuilt.

## Stop Conditions

- Antigravity local JSONL turns out not to carry parseable token usage (P10.04) — pause; fall back to Antigravity HP-only and flag the scope change.
- state.json v5 bump breaks an existing v4 reader path in a way not covered by the writer-always-writes-current-version assumption.
- Broken CI unresolvable within ticket scope, or genuinely ambiguous triage.

## Phase Closeout

Retrospective: required
Why: lays durable architecture (1–100 level engine, two-rulers model, local-token-as-activity proxy, Swift-owned local decay) and seeds follow-up learning (confirmed Cursor/VS Code token boundary, provisional curve re-validation, decay-feel dogfood findings) that shapes later phases.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-10-free-rpg-tier-retrospective.md`
