# Phase 10 Draft — Free RPG Tier (Floating Progression HUD)

_Drafted: 2026-05-27 · Rewritten: 2026-06-03_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: `notes/private/codogotchi-ideation-storm-roadmap-draft.md` §2, `notes/private/free-cloud-plan.md`, `notes/private/stage-100-calibration.md` (operator-local)_
_Supersedes: Phase 12 (level curve + migration) — folded into this phase; see [Relationship to Phase 12](#relationship-to-phase-12)._

---

## Thesis

Ship the **Free RPG tier** as Codogotchi's **default** experience. Every install gets a living, legible pet on the floating frame — **3 Zelda-style hearts** (health), a **level 1–100** indicator, and an **XP ring** whose radius fills toward the next level, with the **level number living inside the ring**. This is a local-first Tamagotchi that needs **no enrollment, no tokens, no URLs, no API keys**.

Progression is **token-only**, drawn from the five platforms phase-09 already reads at parity (**Claude / Codex / Cursor / Antigravity / VS Code**). **No loot, no WakaTime, no GitHub.**

Appearing on the public **leaderboard** (codogotchi.pro / codogotchi.app) is a **separate, opt-in** layer: a frictionless once-a-day sync that seeds the social site with real pets. Decline it and you still keep the full local Tamagotchi.

"Lite" (the old no-chrome tier) is **retired** — the Free RPG tier replaces it as the floor.

---

## Two rulers (state this everywhere)

Tokens feed **two different axes**. They must not be conflated:

| Axis | Meaning | Source | Behavior | Lives |
| --- | --- | --- | --- | --- |
| **Level / XP (the ring)** | "How much have you ever coded" | **Cumulative lifetime tokens** | Monotonic — never decreases | Local; the *level number* is the only thing synced |
| **Health / HP (the hearts)** | "Did you code recently" | **Recency of token activity** | Volatile — decays and recovers in real time | **Local only** — never synced |

XP is accumulation. HP is a streak/recency signal. Same token stream, opposite semantics.

---

## The problem

- Phase 04 deferred all overlay UI; HP and progress accrued silently. Users couldn't tell thriving vs sick, or progress to next level, without CLI `status`.
- The old draft gated all chrome behind an enroll wizard and showed lite users nothing. That conflicts with the new direction: the RPG pet **is** the default.
- The 5-stage ladder is useless for a leaderboard (everyone clumps into 2–3 buckets). The 1–100 curve (formerly Phase 12) is pulled into this phase.

---

## Committed scope

### 1. RPG is the default (no enroll gate for local)

- Local hearts + level + XP ring render for **every** install — no `rpg_enabled` opt-in required.
- The old in-app **enroll wizard dissolves** into a **sync opt-in** flow only (pick a handle, confirm leaderboard appearance). Local RPG needs zero setup.
- Provide an **opt-out** for users who want no chrome (toggle hides the HUD). The HUD remains hidden-by-default-on-hover regardless (see §5).

### 2. Three hearts (local health, real-time decay)

- 3 Zelda-style hearts mapped from `hp` / `hp_overlay` (`thriving` | `getting_sick` | `near_death` | `ghost`).
- **Decay authority is local.** HP is a function of wall-clock time since last token activity, computed on app tick — it must work with **no sync and no opt-in**.
- v1: dimmed heart for half-step decline; no literal half-heart sprite unless cheap.
- **Decay/regen rule (calibrated to owner data):** 3 hearts = **6 half-hearts** = full HP.
  - **Decay:** −½ heart per **8h** with **0 tokens** (any of the 5 platforms). Full → ghost = 6 × 8h = **48h idle**.
  - **Regen:** +½ heart per **1 active coding-hour** (prorated; +¼ at 30 min), capped at full. Ghost → full = **6 active hours**.
  - **Active-hour floor:** an hour counts as "active" only if it contains **≥ ~50K tokens** (tunable) — separates a real agent run from a stray ping. Decay uses strict `0 tokens`; the asymmetry is intentional (any activity pauses decay; meaningful activity heals).
  - All local: computed on app tick from last-token timestamp + per-hour token tallies (phase-09 signals). No sync, no opt-in.

### 3. Level 1–100 (calibrated global curve)

- User-facing **Level 1–100**. Replaces the 5-stage label and threshold table.
- **Single global frozen curve**, calibrated from the **owner's measured 30-day activity** so that ~2 years at that sustained pace reaches level 100.
- **Everyone on the free tier shares this one ruler** — required for a comparable leaderboard. **Per-user re-calibration to one's own activity is a premium feature**, explicitly out of scope here.
- Note: the curve rewards token-heavy (agentic, big-context) work faster than hours-heavy work. Accepted tradeoff for a coding RPG.

**Calibration constants (measured 2026-06-03, owner 30-day window):**

| Constant | Value | Notes |
| --- | --- | --- |
| Metric | **Total tokens (input + output)** | Recommended. Output-only is the one swappable knob (≈275× smaller; anti-inflation alternative). |
| Baseline `B` | **93M tokens/day** | **−50% off owner peak week** (186M/day), agreed meet-in-the-middle. The raw 30-day avg was 71M/day but included a 4-day vacation; vacation-adjusted working-day avg ≈82M/day, so 93M leans deliberately hardcore. |
| Total to L100 `T` | **≈68B tokens** (output-only ≈246M) | `730 × B`. |
| Curve | `C(L) = T × ((L−1)/99)^p`, **`p = 2.5`** | Front-loaded: L50 = 17% of XP (soft first half), L51–100 = 83% (the grind). |

Resulting pace: owner ~4mo to L50, ~24mo to L100 (by construction); pro (~45M/day) ~4.1yr to L100; avg job (~25M/day) ~7.5yr. Representative thresholds: L25 = 1.96B, L50 = 11.7B, L75 = 32.8B, L100 = 68B tokens.

> A 12-month owner window could shift `B` slightly. Re-pull annually if desired; do **not** re-haircut without data.

### 4. XP ring (presentation)

- A **ring** (not a horizontal bar) whose filled radius = within-level progress toward the next level.
- The **level number sits inside the ring**.
- Driven by cumulative token XP vs the new 100-level thresholds.

### 5. Interaction spec

```
Default:     hearts + level ring = hidden
On hover:    show on floating frame
On leave:    hide after short delay
```

Menubar: optional single "needs attention" dot only (defer if costly).

### 6. Data source

- Read cached `~/.codogotchi/profile.json`; HP recomputed locally on tick.
- Hook continues to mirror `hp` on `state.json` for animation-adjacent reads.

### 7. Opt-in sync + leaderboard (gated — see §8)

- **Opt-in only.** Default install never contacts the network.
- **1× per user per day**, with jitter, skip-if-no-new-tokens.
- **Baked prod Convex URL** — no `convex_url` prompt, no tokens, no API key. (Stale line in `notes/private/convex-deployment.md:26` describing the old `codogotchi rpg` URL prompt to be removed.)
- **Syncs `level` + a `last_active` date only.** **Hearts are NOT synced** — they're recency-based and would be up-to-24h stale on the site, painting half the world as "ghost." Leaderboard shows level + last-active.
- Leaderboard surface = **cron snapshot** (`leaderboardSnapshot`), not per-page live queries.

### 8. Launch gate — production deployment + `/sync` auth (NOT UX)

This blocks the **sync/leaderboard half only**. The entire local Tamagotchi ships and demos with none of it done.

- **Cut a `prod` deployment** from the existing Convex project (one project, two deployments: `dev` for owner iteration, `prod` for users). Bake the **prod** URL — never `dev:careful-bat-587` — into the public build.
  - Do **not** split into two projects/teams for quota: Convex Free limits are **per-team**, so two projects share one budget. A single developer's iteration is negligible against the budget anyway; the real quota threat is endpoint abuse, addressed below.
- **Harden `/sync`** (currently unauthenticated; the URL becomes public the moment the build/repo ships):
  - **Apple App Attest / DeviceCheck** — attest requests come from a genuine app instance on a real Apple device. No user credential — fits "no tokens."
  - **Invisible per-install identity** (keypair or server-minted opaque token in Keychain) so only a profile's owner can update it. User never sees it.
  - **Server-side rate-limiting.**
  - **Server-side validation:** level sanity cap (can't exceed what cumulative tokens-since-enroll could produce) + handle moderation (profanity, impersonation, length).

---

## Cost stance (for the plan's risk section)

- **Free Convex is ~8,000 users** at 1 sync/day — the **binding limit is database I/O (1 GB/mo)**, not function calls. Comfortably covers the "seed the social site" goal for a long time.
- **Professional ($25/mo flat for one developer)** raises the included ceiling to **~400,000 users**, then ~**$0.14 per additional 1,000 users/month**. Capacity stops being the constraint the moment you pay.
- **Do not pre-pay.** Stay free through the first several thousand users; flip to Professional the day the hard caps need to go.
- The thing that actually protects the budget is **`/sync` auth** — an open endpoint lets an attacker run up overages for you. Auth > plan tier.

---

## Relationship to Phase 12

Phase 12 (Level Curve 1–100 + Migration) is **folded into this phase and retired as a standalone**:

- The 100-level engine curve and HUD rewire land here (§3, §4).
- "Migration" was 5-stage → 100-level for existing enrolled profiles — per the Convex validation log that's **owner + one buddy**, a trivial one-shot, not a phased dual-write effort.
- The old Phase 12 Cursor-mislabel warning is **stale**: phase-09 delivered five-platform attribution parity.

---

## Defers

- Health tint / sick-idle sprites → **Phase 11**.
- Premium **per-user curve recalibration** (each user's own 30-day baseline) → paid Alive tier.
- Loot, GitHub PR XP, WakaTime XP, 15-minute sync, 24-frame premium sheets → paid Alive tier.
- Level-up celebration policy (every level vs milestones 10/25/50) → decide in plan.

---

## Exit conditions

**Local (no backend dependency):**
1. Any fresh install hovers the floating pet and sees 3 hearts + level + XP ring — no enroll, no network.
2. Hearts decay and recover **locally** from token-activity recency with sync off and no opt-in.
3. Level reflects the calibrated 1–100 global curve; ring shows within-level progress.
4. Opt-out hides all chrome.

**Sync / leaderboard (gated on §8):**
5. `prod` deployment cut; **prod** URL baked into the public build (never `dev:`).
6. `/sync` hardened: App Attest + per-install identity + rate-limit + server-side validation (level cap, handle moderation).
7. Opt-in sync writes **level + last_active only** (hearts never leave the device), max 1×/day.
8. Leaderboard renders from a cron snapshot.

---

## Dependencies

- **Phase 05** `rpg_enabled` flag (semantics shift to default-on / opt-out).
- **Phase 09** five-platform token parity (Claude / Codex / Cursor / Antigravity / VS Code) — **delivered**.
- **Phase 08** Settings shell + install API (sync opt-in flow reuses it; no separate enroll wizard).

---

## Open questions

1. **Token metric:** total (in+out) vs output-only. Recommended **total**; flagged in §3 as the one swappable knob (≈275× swing).
2. **Curve exponent:** `p = 2.5` recommended; `p = 2` softens the late grind if ~2 weeks/level near the top feels too steep.
3. HUD during demo mode?
4. Level-up celebration policy (per-level vs milestone-only).
5. Exact sync payload size to firm up the cost model (affects function-call capacity).
6. Active-hour token floor for regen (~50K) — confirm in plan.

_Settled this round: default-on RPG (no enroll), local decay rule (§2), 1–100 calibration constants (§3, baseline 93M/day = −50% off peak → T≈68B, p=2.5), one-project/two-deployment, `/sync` auth gate, cost stance._

---

## Next step

`/soa plan docs/product/drafts/phase-10-floating-progression-hud.md`
