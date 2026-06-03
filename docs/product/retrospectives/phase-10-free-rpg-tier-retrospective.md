# Phase 10 — Free RPG tier (local floating progression HUD) retrospective

Source plan: [`docs/product/plans/phase-10.md`](../plans/phase-10.md).
Delivery plan: [`docs/product/delivery/phase-10/implementation-plan.md`](../delivery/phase-10/implementation-plan.md).

## Scope delivered

Tickets P10.01 → P10.09 (9/9) landed on stacked branches `agents/p10-01` through `agents/p10-09`, opening PRs [#96](https://github.com/cesarnml/codogotchi/pull/96) through [#105](https://github.com/cesarnml/codogotchi/pull/105) (P10.09 PR pending at closeout). Delivered:

- Frozen 1–100 level curve (`LEVEL_T = 68e9`, exponent `2.5`, baseline ~93M tokens/day) with `levelForXp` / `levelProgress` (P10.01);
- Local half-heart model: decay floor then heal, ghost revives by coding, constants in contracts (P10.02);
- `state.json` schema v5 + `rpg_hud_enabled` opt-out + local-RPG config shape (P10.03);
- Antigravity token reader **stop condition**: transcripts have no token counts → HP-only, documented in contracts (P10.04);
- CLI “brain”: incremental JSONL cursors, v5 writer when `rpg_enabled: true`, active-minute heal proxy (P10.05);
- Swift v5 reader + `HalfHeartDecayEngine` (local decay only, no heal in Swift) (P10.06);
- Floating HUD: hearts, XP ring, Zelda flashes, hover show/hide (P10.07);
- Settings **RPG** tab: HUD disable toggle + demo mode (P10.08);
- This retrospective + documentation sweep (P10.09).

## What went well

**Split loop ownership held.** TS owns XP + heal on hook events; Swift owns decay from `last_activity_at`. No cross-process timer fights, and the contract hands Swift finished numbers (`level`, `level_fraction`, `half_hearts`) so render logic stays dumb. The split is worth repeating whenever one stream feeds two semantics (accumulation vs recency).

**Incremental JSONL cursors prevented double-count and full rescans.** `last_read_at_claude` / `last_read_at_codex` as ISO cursors plus carried `active_minutes` remainder made heal progress stable across rapid hook bursts without WakaTime-grade precision.

**Doc-only stop on Antigravity before code.** P10.04 verified live transcripts first, recorded HP-only fallback in ticket rationale and `jsonl-parser.ts` comments, and avoided shipping a reader that would always return zero XP. That saved a fake “green” ticket and kept the Cursor/VS Code boundary honest (three platforms with rings, two HP-only).

**Subagent review caught real config-path gaps.** P10.03’s `rpg_hud_enabled` was in the Zod schema but missing from `config get/set` until the subagent pass — a classic “schema without CLI surface” hole.

## Pain points

**Plan vs shipped: `rpg_enabled` is still the local progression gate.** The product plan called for default-on RPG without enrollment; fresh app bootstrap and `codogotchi setup` still write `features.rpg_enabled: false`, and the v5 hook writer only runs when `rpg_enabled === true`. The HUD defaults **on** (`rpg_hud_enabled` absent → true), but hearts/level stay inert until the user enables local RPG (today: `codogotchi rpg` or manual config). Avoidable waste for the “clean install hero path” — fix belongs in bootstrap/default config, not more HUD polish.

**Decay/heal feel is provisional, not validated.** Owner+buddy dogfood noted the −½ heart / 8h and +½ / active-hour cadence is playable but not tuned; idle catch-up on laptop sleep works (floored at empty) yet can feel abrupt. Expected cost for v1, but the retrospective must not pretend the constants are final — they are explicitly provisional until distribution data exists.

**README and runbooks still described Phase 05 “Lite vs Alive + Convex URL”.** Documentation debt accumulated across eight prior phases; P10.09 sweep fixes public docs, but operator-local notes under `notes/private/` (gitignored except swift-notes) still need manual edits on the developer machine.

## Surprises

**Antigravity `agy` transcripts are step logs, not token logs.** Gemini CLI sessions elsewhere on disk do carry token fields, but they are a different product — hooks target Antigravity, so the stop condition was correct, not a parser bug.

**Gemini vs Antigravity path confusion is easy.** Future agents should not assume `~/.gemini/` implies token JSONL for Codogotchi; read P10.04 rationale before re-opening P10.04 scope.

**HUD visible while progression disabled.** Default `rpg_hud_enabled: true` with `rpg_enabled: false` can show an empty or stale ring — intentional opt-out ergonomics, surprising for “Free RPG as floor.” Documented here so Phase 11/bootstrap work does not re-litigate it silently.

## What we'd do differently

**Flip default `rpg_enabled` to true in app bootstrap** once local-only config is validated, and split “cloud enroll” from “local RPG on” in CLI copy. Original reasoning kept Phase 05 guards and Convex enrollment coupled; Phase 10 proved local RPG needs no URL — the guard should gate `sync`, not the v5 writer.

**Single “platform XP matrix” doc checked in at P10.03.** Cursor/VS Code HP-only and Antigravity HP-only were spread across tickets, contracts comments, and plan prose — a one-table doc would have shortened P10.05/P10.07 review.

**Earlier animation-state contract bump to v5.** Contract doc stayed at v4 until P10.09; code and tests were on v5 from P10.03 — doc lag invited drift.

## Net assessment

Phase 10 achieved its core technical goal: a local, network-free progression loop with honest platform boundaries, v5 state, floating HUD, and settings opt-out. The product “default hero” goal is **partially** met: visuals and architecture are ready, but first-run still behaves like Lite until `rpg_enabled` is flipped. Antigravity and Cursor/VS Code boundaries match the grilled plan. Provisional curve and decay constants are shipped with eyes open. The phase is shippable as v1 local RPG; notarization/DMG is the right next effort, not sync.

## Follow-up

1. **Bootstrap default** — set `features.rpg_enabled: true` on first launch (local RPG only); keep Convex fields optional; gate `sync` on cloud config presence. Track in Phase 11 or a small standalone PR.
2. **Notarized DMG / distribution** — next product milestone per plan; no sync work beforehand.
3. **Operator-local doc sweep** — update `notes/private/convex-deployment.md`, `stage-100-calibration.md`, `free-cloud-plan.md` on the machine that holds them (not in public repo).
4. **Re-validate curve** — when real token distribution exists, re-check `T = 68e9` and `p = 2.5`; per-user recalibration stays premium.
5. **Sick-idle / health-tint art** — deferred art phase; HUD uses flashes, not tint rows.
6. **Phase 11** — opt-in sync + leaderboard + enroll; do not block on decay polish.

_Created: 2026-06-03. PR stack #96–#104 merged or open; P10.09 closes docs._
