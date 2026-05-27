# Codogotchi ideation storm — roadmap draft

**Purpose:** Input for upcoming `/soa ideate` → `docs/product/drafts/<slug>.md` → `phase-05+` product plans.  
**Date:** 2026-05-27  
**Status:** Developer ideation capture — not approved scope  
**Audience:** Future planning sessions; cross-reference with technical research in `notes/public/`

---

## How to use this document

1. Run the **ideation storm** (XP / level / health / HUD / settings / monetization) using this file as the north star.
2. Feed this doc plus linked artifacts into **`/soa ideate`** to produce one or more phase drafts.
3. Split work by repo where needed:
   - **Codogotchi** (`~/code/codogotchi`) — UI, sync, hooks, Convex, assets, settings window.
   - **Son-of-Anton** (`~/code/son-of-anton`) — e.g. direct gate writes to `~/.codogotchi/`, alignment contracts.

**Related technical research (prior conversations):**

| Topic | Artifact |
| --- | --- |
| Native Codex parity (~90%), attention tray gap | [codogotchi-native-codex-pet-feature-parity-roadmap.md](./codogotchi-native-codex-pet-feature-parity-roadmap.md) |
| Platform hooks, signal pipeline, work-mode, SoA direct-write | [codogotchi-platform-extension-and-signal-pipeline-research.md](./codogotchi-platform-extension-and-signal-pipeline-research.md) |
| Multi-platform hook sizing | [multi-platform-hook-support.md](./multi-platform-hook-support.md) |
| Native Codex pet triggers (reference) | [codex-native-pet-animation-triggers.md](./codex-native-pet-animation-triggers.md) |
| Event-driven animation + mouse | [codogotchi-event-driven-mouse-interaction-implementation.md](./codogotchi-event-driven-mouse-interaction-implementation.md) |
| Phase ladder context | [codogotchi-phase-04-05-roadmap.md](./codogotchi-phase-04-05-roadmap.md) |
| SoA ↔ codogotchi alignment | [.son-of-anton/notes/public/codogotchi-alignment-draft.md](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md) |

---

## Executive snapshot

**Where we are:** ~**90% feature parity** with the **native Codex desktop pet** for animation and floating-window behavior. Codogotchi **exceeds** native in several dimensions (persistent menubar pet, SoA-aware states, hook-driven implementing/testing heuristics, richer activity vocabulary).

**Primary native gap:** **Attention UX** when the agent needs the user — native Codex shows a **chat bubble** (short reason), dismiss → **notification badge** with count, click → focus Codex app. Codogotchi has the **waving** animation (`requesting_input` / Codex row 6) but **no bubble, no tray, no deep-link focus**.

**Next big bet:** Make **progression and health legible** on the **floating pet** — Zelda-style hearts, WoW-style XP bar, level badge — plus a **settings window** and a **pet + loot** economy tied to Codex pets and optional premium layers.

---

## 1. Current state vs native Codex pet

### 1.1 At parity or better (shipped / near-shipped)

| Capability | Codogotchi | Native Codex pet |
| --- | --- | --- |
| Persistent menubar pet with animation | Yes | No (floating-focused) |
| Floating pet window | Yes | Yes |
| Hook-driven work states (implementing, tests, etc.) | Yes (heuristics) | Simpler session/notification model |
| Mouse: hover → jump | Yes | Yes |
| Mouse: drag → run left/right | Yes | Yes |
| Resize / scale frame | Yes | Yes |
| Hide pet (close tooltip, right-click) | Yes | Yes |
| SoA delivery gate animations | Yes (exceeds) | N/A |

### 1.2 Not at parity (target for roadmap)

| Capability | Native Codex | Codogotchi today |
| --- | --- | --- |
| **Attention bubble** — why the pet wants you | Chat bubble with short summary | Animation only |
| **Dismiss → notification icon** with message count | Yes | No |
| **Click bubble/icon → focus agent app** | Focus Codex | No deep link |
| **TTL / decay** when attention is stale | Notification expiry | Can stick on `requesting_input` (see parity roadmap) |

**Product intent:** Implement something **similar** for Codogotchi — bubble + dismiss + badge + focus target (Cursor / Codex / VS Code as platform allows).

---

## 2. Floating pet HUD — health, level, XP

**Design principle:** HUD chrome lives on the **floating pet frame only**, not the menubar icon. Menubar stays minimal. HUD is **hidden by default**; appears on **hover** over the floating frame; **auto-hides after a delay** so it does not obscure the sprite.

### 2.1 Health — Zelda hearts (3 hearts)

**Indicator:** Three small hearts overlaid on the floating frame when HUD is visible.

| Hearts (visual) | Meaning | Activity mental model |
| --- | --- | --- |
| **3** | Thriving | Heavy coding, PRs, signals — pet is healthy |
| **2** | OK | Not thriving, not sick — “doing fine” |
| **1½** | Declining | Starting to look weary; subtle sad/cough **optional** (may defer to tint-only) |
| **≤1** | Sick | Clear visual degradation |
| **0 / ghost** | Expired / dead | Dead idle variant |

**Decay rule (proposed):**

- For every **12 hours without coding activity**, lose **½ heart**.
- Example: miss ~1 day → **2 hearts** (OK band).
- Tune exact signal source in plan phase: WakaTime hours, hook activity, GitHub, sync window, etc.

**Sprite representation (preferred over many new animations):**

- **Tint** on the sprite for degradation stages (simple, shippable).
- **Idle row variants** for health bands (asset cost controlled):
  - Healthy idle
  - Getting sick idle
  - Sicker idle
  - Expired / dead idle

Optional cough/weary **only if** cheap to ship; default to tint + idle variant swap.

**Alignment with existing code:** Engine already has `hp`, `hp_overlay` (`thriving` | `getting_sick` | `near_death` | `ghost`) in contracts and `packages/engine/src/health.ts`. Hearts are a **presentation layer** mapping overlay/HP to 3-heart UI — plan should define the mapping table.

### 2.2 Level indicator (rename from “stage”)

**Terminology change:** User-facing **“level”** (1–100), not “stage.”

**Today in codebase:** `profile.stage` with **5** thresholds in `packages/engine/src/xp.ts` (`STAGE_THRESHOLDS`). This is a **breaking product rename + curve redesign**, not a label swap.

**Target progression model:**

- **100 levels** total.
- Curve is **not linear** — progressively harder per level (quadratic or similar).
- Calibrate so a user whose **30-day activity** is taken as baseline would reach **level 100 in ~2 years** at that average pace.
- Per-user calibration: use rolling 30-day signals to project difficulty (personalized grind, not one global ladder).

**HUD:** Small **circle with level number** (1, 2, 3, …) on floating frame when hover HUD is visible. Already have a stage-like indicator in UI — **relabel and rewire** to new level function.

**Open questions for ideate / grill-me:**

- Migration for existing Convex `stage` field → `level`?
- Whether level-ups trigger celebration animation (`celebrating` / ascended) every time or only milestones?
- Anti-grind caps or rest bonuses?

### 2.3 XP bar — World of Warcraft style

**Indicator:** Horizontal XP bar on floating frame (hover HUD only) showing progress **toward next level**.

**Signals that fill the bar (existing + future):**

- Token burn (Claude / Codex) — already in `computeXp`
- Merged PRs — `XP_PER_GITHUB_PR`
- WakaTime hours — `XP_PER_WAKATIME_HOUR`
- Additional metrics as sync expands

Bar fills as XP accrues within the current level band; on level-up, bar resets with optional flash (cosmetic).

### 2.4 HUD interaction spec

```
Default:     hearts + level badge + XP bar = hidden
On hover:    show all three
After delay: hide (even if still hovering? → decide; default: hide N seconds after mouse leave)
```

Menubar pet: **no** hearts/level/XP chrome (optional future: tiny dot for “needs attention” only).

---

## 3. Settings window (menubar → Settings)

**Entry:** Menubar click → menu includes **Settings** → opens a **new window** (not a tiny panel).

**Tab: General (v1)**

| Setting | Purpose |
| --- | --- |
| **WakaTime API key** | Drive hours → XP / health signals |
| **GitHub username** | PR / activity signals |
| **Pet selection** | Choose which pet sprite set to use |

**Pet selection strategy:**

- **Today:** Hardcoded to one pet — not viable long-term.
- **Default path:** **Codex pet integration** — if you use Codex pets, Codogotchi works with **no extra config** (read pet from Codex install / config).
- **Future tabs** (defer in ideate unless storm says otherwise): Hooks, Notifications, Premium, Loot.

Store secrets locally (Keychain on macOS); sync profile fields to Convex as today’s model allows.

---

## 4. Pets, Codex integration, premium

### 4.1 Codex pets as the default catalog

**Selling point:** “Use your Codex pet in Codogotchi with zero setup.”

- Enumerate pets from Codex asset/layout conventions (exact integration TBD in plan).
- Settings override only when user wants a non-default.

### 4.2 Premium — Son of Anton enhanced animations

**Premium service:** Animations that reflect **SoA delivery gates** and orchestration soul (hyped, celebrating, calling_for_backup, etc.) — already partially exist; productize as **enhanced animation pack** for paying users.

Free tier: hook heuristics + basic states. Premium: full gate vocabulary + possibly custom sprites per gate.

### 4.3 Loot — static assets + minimal equip (premium to *use*)

**Loot library:**

- Generate **~200 static loot icons** (WoW-style icon sheet aesthetic).
- **Not premium to own/view** — assets ship with app or download pack.

**Equip slots (minimal v1):**

| Slot | Examples |
| --- | --- |
| **Hand** | Sword, staff, book |
| **Head** | Hat / headgear |

**Premium:** Actually **equipping** loot on the pet (render layered on sprite). Free users see catalog; premium enables wear.

**Stretch:** Pet-on-pet (“your pet has a pet”) — premium or later phase.

**Art pipeline:** Bulk-generated icons + small set of attachment anchors on pet rig (hand, head).

---

## 5. Technical backlog already identified (fold into phases)

These came from prior research; **not** repeated in full here — attach to phases during ideate:

| Theme | Summary | Primary repo |
| --- | --- | --- |
| **Attention tray + TTL** | Bubble, badge, focus app, decay stale `requesting_input` | Codogotchi |
| **Multi-platform hooks** | Cursor, VS Code Copilot, Antigravity adapters | Codogotchi |
| **Signal honesty** | Fix `claude_code` mislabel for Cursor; log shell commands | Codogotchi |
| **Work-mode taxonomy** | Thinking / Implementing / Testing heuristics | Codogotchi |
| **SoA direct write** | Gates → `~/.codogotchi/` when enabled | **Son-of-Anton** + codogotchi reader |
| **Platform extension** | See platform research doc | Codogotchi (+ SoA upstream bit) |

Suggested **phase bucketing** for ideate (draft names only):

| Draft phase | Theme |
| --- | --- |
| **05** | Floating HUD — hearts, level rename, XP bar, hover chrome |
| **06** | Health sprites — tint + idle variants, decay tied to signals |
| **07** | Attention tray — bubble, badge, focus, TTL |
| **08** | Settings window + WakaTime / GitHub / pet picker |
| **09** | Codex pet catalog integration |
| **10** | Level curve (100 levels / 2-year calibration) + Convex migration |
| **11** | Loot library + equip rendering (premium gate) |
| **12** | Premium SoA animation pack + platform hooks (may split) |

Numbers are **illustrative** — ideate may merge or reorder.

---

## 6. Monetization sketch (for ideate, not pricing)

| Tier | Includes |
| --- | --- |
| **Free** | Menubar + floating pet, hook animations, Codex pet passthrough, loot catalog view |
| **Premium** | Equip loot, SoA-enhanced animation pack, possibly faster sync / cloud profile extras |

Loot **assets** are free; **equip behavior** is premium. Aligns with “generate hundreds of icons, charge for expression.”

---

## 7. Success criteria (draft — refine in `/soa plan`)

1. User can see **3-heart health** and understand thriving vs sick without opening docs.
2. User can see **level N** and **XP to N+1** on hover without cluttering idle view.
3. Level **100** is achievable in ~**2 years** for a baseline derived from their own 30-day activity (document formula).
4. Attention state shows **why** (bubble) and does not stick forever (TTL + badge).
5. Settings window configures WakaTime, GitHub, and pet without editing JSON by hand.
6. Codex pet users get **zero-config** pet appearance.
7. Premium clearly adds **equip + SoA soul animations**, not core pet visibility.

---

## 8. Explicit deferrals (candidate — challenge in grill-me)

- Public web armory / OAuth / leaderboard (May 16 drafts) — still long-horizon.
- Full 200-loot equip slots beyond hand + head in v1.
- XP/sync for Cursor-only agents without Claude/Codex JSONL.
- Android / non-macOS clients.
- Pet-on-pet companion.

---

## 9. Open questions for ideation storm

1. **Heart decay:** What exactly counts as “coding” — WakaTime only, hooks, GitHub commits, or composite?
2. **Half-heart UI:** Literal half-heart sprite vs 3 hearts where middle heart is “dimmed”?
3. **Level migration:** Rename `stage` in API/Convex or dual-write during transition?
4. **2-year curve:** Fixed formula from 30-day baseline vs periodic recalibration (could feel unfair if life changes)?
5. **Attention focus target:** Codex only, or Cursor/VS Code deep link per `source_origin`?
6. **HUD delay:** Hide after mouse leave only, or also timeout while hovering?
7. **Premium billing:** StoreKit subscription vs one-time vs “Codogotchi Pro” tied to Convex account?
8. **Loot rig:** One pet rig for v1 or per-Codex-pet attachment points?

---

## 10. Suggested `/soa ideate` prompt (copy-paste starter)

> Ideate phase-05+ for Codogotchi from `notes/public/codogotchi-ideation-storm-roadmap-draft.md`. Focus: floating HUD (hearts, 100-level curve, XP bar), health visuals (tint + sick idles), attention tray parity with native Codex, settings window (WakaTime, GitHub, pet picker), Codex pet zero-config, loot catalog + premium equip, premium SoA animations. Pull in platform/signal research and parity/TTL docs. Split codogotchi vs son-of-anton upstream (SoA ~/.codogotchi gate write). Produce multiple draft slugs if scope is too large for one phase.

---

## 11. Glossary

| Term | Meaning in this doc |
| --- | --- |
| **Native Codex pet** | Pet inside Codex desktop app (not Codogotchi) |
| **Stage** | Legacy codogotchi term (5 tiers) — **replace with level** |
| **Level** | User-facing 1–100 progression |
| **HUD** | Hearts + level circle + XP bar on floating frame |
| **Loot** | Cosmetic icon + optional equipped render on pet |
| **Premium** | Paid equip + SoA animation pack (boundaries TBD) |
