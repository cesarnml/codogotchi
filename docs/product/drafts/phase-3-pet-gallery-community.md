# Codogotchi — Phase 3: Pet Gallery + Community
_Draft — approved 2026-05-16_

## Goal

Add visual identity via pet rendering, launch guild competition, and automate social amplification.

**Success gate:** Listed on petdex.crafter.run, 5,000 GitHub stars, 500 active profiles.

---

## Scope

1. **Pet preview on armory profiles**
   - codex-pets manifest API — fetch user's active pet
   - 3-frame idle GIF rendered on `/[username]`

2. **Pet selection UI on armory**
   - Browse and equip pets from codex-pets ecosystem
   - Replaces/extends the Phase 2 web equip UI

3. **Leaderboard pet sprite thumbnails**
   - Small pet icon next to each username on `/leaderboard`

4. **Submit to petdex.crafter.run**
   - List Codogotchi as official XP layer integration
   - Drives discovery from the pet ecosystem

5. **Guild system — explicit invite groups**
   - Create guild, invite members by GitHub username
   - Guild leaderboard (scoped to members)
   - Guild profile page

6. **Seasonal loot events**
   - Time-boxed limited drops (e.g. launch anniversary, holidays)
   - Guaranteed rare+ during event window

7. **Discord bot**
   - Loot drops → server channel notification
   - Stage-ups → server channel notification
   - Per-server config (which events to broadcast, which channel)

---

## Decisions Locked

| Question | Answer |
|---|---|
| Guild membership | Explicit invite groups (not GitHub org auto-detection) |
| openpets | Competitive reference only — no integration or partnership |

---

## Explicitly Deferred

- Monetization (Phase 4, post-validation only)
  - Premium cosmetic packs ($2.99–$4.99)
  - Seasonal battle pass ($4.99/mo)
  - Org leaderboards paid tier ($19/mo)
  - Core XP, public profiles, global leaderboard: free forever

---

## Dependencies

- Phase 2 shipped: friends system, achievement badges, HP reveal all live
- codex-pets manifest API is stable and publicly accessible
- petdex.crafter.run accepts submissions

---

## Next Step

`/soa plan docs/product/drafts/phase-3-pet-gallery-community.md`
