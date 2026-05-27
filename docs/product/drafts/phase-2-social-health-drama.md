# Codogotchi — Phase 2: Social + Health Drama
_Draft — approved 2026-05-16_

## Goal

Reveal the health system, launch the social graph, and create the first viral sharing moments.

**Success gate:** 1,500 GitHub stars, 50 friend relationships, first epic+ loot drop posted publicly.

---

## Scope

1. **HP bar + health state on `/[username]` profile**
   - States: Thriving 💚 → Struggling 🟡 → Critical 🔴 → Dead 💀
   - HP was accumulating silently since Phase 1 — this is the reveal

2. **Death tombstone on armory profile**
   - Cause of death, date of death
   - Displayed in place of normal stats when `hp === 0`

3. **Ghost indicator on leaderboard**
   - 💀 next to username for dead pets

4. **Revival notification in CLI**
   - Dramatic output on next `codogotchi sync` after death
   - Pet revives at minimum HP; death count increments

5. **Friends system — mutual follow**
   - Add by GitHub username
   - Follow request → accept flow
   - Reactive friend list

6. **Friend feed events**
   - Stage-ups, epic+ loot drops, achievement unlocks, deaths
   - Live-updating via Convex reactive query

7. **Friends-only leaderboard filter**

8. **Achievement badges on armory profile**
   - Display badges already tracked in DB since Phase 1

9. **Epic+ loot drop share cards**
   - Auto-generated image via `@vercel/og`
   - One-click share to Twitter/X

10. **Web equip UI**
    - Item selection from inventory on armory profile
    - CLI `codogotchi equip` already works; this adds the web surface

11. **Stage 5 (Ascended) unlock flow**
    - Special notification in CLI
    - Visual distinction on armory profile

12. **Full loot table expansion**
    - 60+ items across 5 rarities (up from 18 in scaffold)

13. **MCP server**
    - `record_activity` — lets other tools push activity signals
    - `get_pet_status` — exposes current pet state to MCP clients

---

## Decisions Locked

| Question | Answer |
|---|---|
| Friends model | Mutual — follow request + accept |
| MCP server timing | Phase 2 |

---

## Explicitly Deferred

- Guild system (Phase 3)
- Discord bot (Phase 3)
- Pet preview from codex-pets API (Phase 3)
- Monetization (Phase 4, post-validation only)

---

## Dependencies

- Phase 1 shipped and health fields live in Convex schema
- HP has been accumulating in prod — users will have real data on reveal

---

## Next Step

`/soa plan docs/product/drafts/phase-2-social-health-drama.md`
