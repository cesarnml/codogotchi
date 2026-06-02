# Phase 14 Draft — Premium SoA Animation Pack

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: ideation storm §4.2, §6 monetization sketch_

---

## Thesis

**Free lite** users get hook heuristics + standard Codex/Codogotchi rows. **Premium** users get the full **SoA delivery soul**: `hyped`, `celebrating`, `calling_for_backup`, `panicking`, etc. as a productized **enhanced animation pack** — not a paywall on seeing the pet.

Pair with **Phase 07** global gate feed so gates fire when hooks are quiet.

> **⚠️ Premise update (2026-05-30, from Phase 08 planning) — re-aim before `/soa plan`:** Phase 08 ships **SoA gate animations for free** (Lite + SoA fully supported, no enrollment, no Convex) on the **8-frame** lite + SoA sheets. So premium is **no longer** "unlock the SoA soul animations" — those are free. The premium animation axis is now the **24-frame high-fidelity pack**: v1 free tier renders **8 frames/row at 1.5 s**; premium renders **24 frames/row** (smoother motion, same states). This draft's thesis, scope, and exit conditions below were written against the old "gate SoA behind premium" model and must be reworked around the 24-frame pack (+ Phase 13 loot equip). The old vocabulary below (`hyped`, `celebrating`, `calling_for_backup`, `panicking`) is also **deleted** under schema v4 — see [phase-07 plan](../plans/phase-07-signal-honesty-and-soa-global-gates.md).

---

## The problem

- SoA states exist in contract and sheets; all users see them today when `.soa/events.ndjson` fires.
- Monetization sketch: premium = **24-frame animation pack** + loot equip (Phase 13), not core visibility.
- Need explicit entitlement without breaking lite users’ basic agent states.

---

## Committed scope

### 1. Entitlement model

- `premium.soa_animations` (or bundled `premium.pro`) in config / Convex profile
- Free: map SoA gate events to **nearest free state** or **idle** (product decision in plan — must not feel broken during SoA delivery)
- Premium: full `SOA_GATE_TO_STATE` mapping on codogotchi sheet rows

### 2. Renderer behavior

- When gate event received and not entitled: optional subtle menubar badge only, or fallback `implementing` / `waiting` — **plan must choose honest fallback**
- When entitled: current Phase 03 behavior

### 3. Marketing boundary in app

- Settings → About or Premium section: lists what Pro adds (24-frame pack + equip from Phase 13)
- No paywall on menubar/floating pet existence

### 4. Docs

- README tier table; troubleshooting for “I use SoA but pet doesn’t celebrate”

---

## Defers

- StoreKit / subscription implementation
- Custom sprites per gate (same sheet, different art) — stretch
- Faster sync / cloud profile extras mentioned in ideation

---

## Exit conditions

1. Free account: `ticket_completed` does not show `celebrating` row (per chosen fallback policy).
2. Premium account: same event shows `celebrating`.
3. Global gate file (Phase 07) drives premium mapping without repo hook fire (runbook).

---

## Dependencies

- **Phase 07** SoA global gates (strongly recommended)
- **Phase 13 loot** premium entitlement infrastructure (shared flag OK)

---

## Next step

`/soa plan docs/product/drafts/phase-14-premium-soa-animation-pack.md`
