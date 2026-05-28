# Codogotchi distribution and monetization stance

Date: 2026-05-28  
Status: Product direction (conversation artifact, not shipped)  
Related: [codogotchi-process-cost-and-menubar-static-rendering.md](./codogotchi-process-cost-and-menubar-static-rendering.md), [phase-12-loot-equip-companion-and-custom-pets.md](../docs/product/drafts/phase-12-loot-equip-companion-and-custom-pets.md), [phase-13-premium-soa-animation-pack.md](../docs/product/drafts/phase-13-premium-soa-animation-pack.md), [phase-05-through-14-roadmap-index.md](../docs/product/drafts/phase-05-through-14-roadmap-index.md)

---

## Executive summary

**Distribution (stance):** Ship **free Codogotchi** via **notarized DMG + Sparkle** (and optionally Homebrew), following the **CodexBar** model — not Mac App Store for v1. App Store is a **later discoverability channel** once hooks, CLI bundling, permissions, and payment rails are settled.

**Monetization (stance):** Do **not** charge for the menubar/floating pet or core hook pipeline. Revenue is on the **RPG expression layer**: loot you earned → pay to **wear** it on the pet via **row-compatible spritesheet overrides** (optionally **server-generated** from loot card + base sprite + chosen target animation row).

This aligns with Phase 12 (loot equip, per-row sheets, premium generation) and Phase 05 explicit deferral of App Store as a lite-install gate.

---

## 1. App Store vs DMG / direct distribution

### 1.1 Comparison

| Factor | DMG / direct (CodexBar-style) | Mac App Store |
| --- | --- | --- |
| **Hooks + `codogotchi-hook`** | Install into `~/.claude`, `~/.codex`, Cursor; spawn on agent lifecycle | Sandboxing conflicts with editing other apps’ config and broad home-dir access |
| **CLI on PATH** | `brew`, install script, docs; bundle in `.app` deferred to distribution milestone | Review expects self-contained app; Phase 05 defers PATH-free bundle |
| **Permissions** | Full Disk Access, Keychain, agent dirs — document in README | Same APIs possible; entitlements + review narrative harder |
| **Updates** | Sparkle / `brew upgrade` — fast hook fixes | Review latency per release |
| **Payments** | Stripe/Paddle + account → Convex entitlement | StoreKit / IAP for digital unlocks consumed in-app |
| **Discovery** | GitHub, community, adjacent tools (CodexBar) | Store search, trust |
| **Revenue share** | Payment processor fees only | Apple 15–30% on IAP |

### 1.2 Why Codogotchi is a direct-distribution product first

Codogotchi is a **menubar agent + hook sidecar**, not a self-contained sandboxed utility:

- Reads/writes `~/.codogotchi/state.json`; installs hook commands into agent config.
- Depends on **Son-of-Anton** and multi-platform hook paths (Cursor, Claude, Codex).
- Phase 05 lite install runbook: **explicitly not App Store** for exit validation.

CodexBar stays direct partly for the same reason: provider CLIs, cookies, Keychain, optional Full Disk Access.

### 1.3 When App Store becomes worth it

**DMG is not a distribution stopgap — it is the right permanent model for this product.** Codogotchi's core value prop is sandbox-hostile: it writes to `~/.claude/settings.json`, `~/.codex/hooks.json`, and spawns `codogotchi-hook` on agent lifecycle events. App Store sandboxing fights every one of those requirements. The target audience (AI developers) already installs Cursor, Warp, and CodexBar via DMG without friction — the trust and discoverability arguments for App Store do not apply here.

**GitHub Releases + notarized DMG + Sparkle** (+ optional `brew install --cask`) is the release model through v1 and likely beyond. Do not treat App Store as an implied next phase; treat it as a deliberate strategic pivot to revisit only if non-developer user acquisition becomes a priority.

**The DMG story closes completely at Phase 10** when the `codogotchi` CLI binary is bundled inside `Contents/MacOS/`. After that, the DMG is a fully self-contained drag-and-drop artifact — no PATH prerequisite, no brew install, no Terminal required.

Consider Mac App Store only when:

- Hook installer and CLI are **bundled** in `.app` with a clear permissions story.
- Release cadence can tolerate **review delay**.
- In-app premium unlocks use **IAP** (or a vetted “account / reader” model with legal review).
- **Non-developer discovery** justifies the overhead.

Until that strategic pivot is made explicitly: **GitHub Releases + notarized DMG + Sparkle** (+ optional `brew install --cask`).

### 1.4 Frontend analogy (dev server vs production bundle)

Xcode **Debug** (`-Onone`, debugger) ≈ frontend dev server; **Release** (`.app`, `-O`) ≈ production bundle. That affects **perf expectations**, not the App Store vs DMG choice — both are native ARM binaries.

---

## 2. Monetization model

### 2.1 Free vs paid boundary

| Tier | Includes | Does not include |
| --- | --- | --- |
| **Free (Lite)** | Menubar + floating pet, hooks, standard sprite rows, SoA gates visible today (policy may evolve in Phase 13) | Paid row generation, premium equip wear |
| **Alive (RPG, opt-in)** | XP, health, loot drops, sync (`codogotchi enroll`) | Automatic paid cosmetics |
| **Premium (paid)** | Equip loot on pet; optional **custom row generation**; optional SoA animation pack (Phase 13) | Core pet visibility, basic agent states |

**Do not paywall** “having a pet” or basic `activity_state` mirroring. Charge for **expression**: wearing loot and custom row art.

### 2.2 Proposed paid workflow (conversation 2026-05-28)

User-facing flow:

1. User earns or receives **loot** (card art + metadata in RPG layer).
2. User chooses a **supported animation row** to replace (mapped to `ActivityState` / contract rows — e.g. `implementing`, `celebrating`, not arbitrary names).
3. **Paid service** merges **loot card + Codogotchi base sprite** (+ optional user prompt or curated prompt template) via image model (e.g. GPT image generation).
4. Pipeline outputs a **grid-validated** `spritesheet.webp` (8-frame Codex row or 24-frame Codogotchi row per target).
5. App installs under equip path and **swaps that row** at runtime when entitled + equipped.

Pre-authored catalog (~200 loot icons, Phase 12 draft) can exist **without** generative AI; paid tier adds **generation + equip**.

### 2.3 Alignment with Phase 12 draft

Phase 12 already specifies:

- `~/.codogotchi/pets/<id>/equip/<loot-id>/` with `meta.json` (slot, **target rows**) + `spritesheet.webp`.
- Renderer prefers equip sheet for matching `activity_state` when premium entitled.
- **BYOP** for power users (folder drop-in without paid generation).
- **Premium custom pet generation** as a service boundary (manual ops → automate).

The conversation model is Phase 12 §6 with explicit **user-selected target row** and generative merge from loot card + base sprite.

### 2.4 Phase 13 (SoA animation pack) — separate SKU?

Phase 13 draft: premium = full SoA gate row mapping vs free fallback on gate events.

**Recommendation:** Bundle into one **“Pro”** entitlement early, or keep loot-equip and SoA-pack as two flags (`premium.equip`, `premium.soa_animations`) to avoid three confusing SKUs at launch.

---

## 3. Service architecture for paid generation

Server-side pipeline (preferred over API keys in app):

```
loot card asset + base sprite + target_row_id + optional prompt
  → generation job (queued)
  → QA: grid dimensions, frame count, divisibility, content policy
  → deliver equip bundle to profile / download into ~/.codogotchi/pets/.../equip/<loot-id>/
  → renderer row override on match
```

| Concern | Mitigation |
| --- | --- |
| Bad frames / inconsistent motion | Fixed prompts per row type; human QA tier for paid |
| Codex 8-frame vs Codogotchi 24-frame | Price or SKU per grid class; validate before delivery |
| User expects video | Copy: **spritesheet row swap**, not custom video pet |
| Gen cost > price | Credits per generation; preview limits |
| Moderation (uploads + prompts) | Review queue; stricter if App Store build |
| BYOP overlap | Free: drop folders; paid: **generation convenience** |

Contract reference: [animation-state-vocabulary.md](../../docs/contracts/animation-state-vocabulary.md) — row maps and sheet grids.

---

## 4. Payments and channel rules

| Channel | Payment rail | Notes |
| --- | --- | --- |
| **DMG / direct** | Stripe/Paddle + Convex (or local) entitlement | Common for dev tools; unlock in app after sign-in |
| **Mac App Store** | StoreKit IAP / subscription | Required for digital features unlocked **inside** the store build, per Apple guidelines |
| **Hybrid** | Free app everywhere; purchase on web | Possible on direct; App Store build needs legal/IAP review |

Phase 12 defers StoreKit; entitlement stub (Convex field or local flag) is enough until distribution phase.

---

## 5. Recommended sequencing

```text
Phases 05–07     Direct install (DMG/notarized), free lite pet + hooks
Phase 08–12      Settings loot → equip folders → renderer row override
Monetization v1  Web checkout → credits / Pro → generation + equip download
Optional later   Mac App Store build + IAP if discovery warrants it
Parallel         Static menubar, Release perf (see process-cost notes)
```

Repo deferrals already recorded: signing, notarization, Sparkle, App Store enrollment in Phase 05 implementation plan **Out of scope**.

---

## 6. Open questions

- Single **Pro** bundle vs separate loot-gen and SoA-pack SKUs?
- Per-generation credits vs monthly subscription?
- Allow equip on **interaction rows** (`running-left`, `running-right`) or activity states only?
- App Store “free app + manage subscription on website” — legal review before relying on it.
- Whether SoA celebrating/hyped should remain free for all SoA users (Phase 13 policy) when monetizing loot wear.

---

## 7. Bottom line

- **Ship free via DMG/direct** like CodexBar; **App Store later**, not v1.
- **Charge for RPG expression** (loot → row spritesheet), not for the app binary.
- **User picks supported animation row**; pipeline validates grid and installs equip assets — matches Phase 12 and existing renderer contract.
- **Direct distribution + web pay** first; add **IAP** when/if a Store build exists.
