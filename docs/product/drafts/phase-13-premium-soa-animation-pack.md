# Phase 13 Draft — Premium SoA Animation Pack

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: ideation storm §4.2, §6 monetization sketch_

---

## Thesis

**Free lite** users get hook heuristics + standard Codex/Codogotchi rows. **Premium** users get the full **SoA delivery soul**: `hyped`, `celebrating`, `calling_for_backup`, `panicking`, etc. as a productized **enhanced animation pack** — not a paywall on seeing the pet.

Pair with **Phase 07** global gate feed so gates fire when hooks are quiet.

---

## The problem

- SoA states exist in contract and sheets; all users see them today when `.soa/events.ndjson` fires.
- Monetization sketch: premium = **SoA soul animations** + loot equip (Phase 12), not core visibility.
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

- Settings → About or Premium section: lists what Pro adds (SoA pack + equip from Phase 12)
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
- **Phase 12** premium entitlement infrastructure (shared flag OK)

---

## Next step

`/soa plan docs/product/drafts/phase-13-premium-soa-animation-pack.md`
