# Codogotchi — Phase 1: CLI + Armory
_Draft — approved 2026-05-16_

## Goal

Ship `npm install -g codogotchi-xp` and `codogotchi.pro/username` good enough to post on Twitter.

**Success gate:** A real profile populated from real activity, live on Vercel. The leaderboard renders. The OG image shares cleanly.

---

## Scope

1. **Rename pass — first, before any new code**
   - `claude-pet` → `codogotchi` everywhere
   - `~/.claude-pet/` → `~/.codogotchi/`
   - npm package: `codogotchi-xp`
   - CLI command: `codogotchi` (alias: `cdog`)
   - Hook binary: `codogotchi-hook`
   - All scaffold references, `package.json`, bin entries, README, `install.sh`

2. **Wire health system into engine (silent — no web UI)**
   - `tickHealth()` called on every `sync`
   - `scorePR()` called on every PR merge in `applyPRMerge`
   - HP accumulates damage silently; no display anywhere in Phase 1

3. **Update Convex schema with health fields**
   - Add to `profiles` table: `hp`, `died_at`, `cause`, `death_count`

4. **Convex backend**
   - `syncProfile` mutation (receives raw signals, recomputes XP server-side)
   - `getLeaderboard` reactive query
   - `getProfile` reactive query (full profile + rank)
   - HTTP actions to receive syncs from `codogotchi-xp` CLI

5. **GitHub OAuth via NextAuth.js**

6. **Next.js 15 armory — codogotchi.pro**
   - `/` landing page
   - `/[username]` public armory profile (ISR, 60s revalidation) — static placeholder avatar
   - `/leaderboard` live leaderboard (`useQuery` Convex subscription)
   - `/api/og/[username]` dynamic OG image (Edge runtime, `@vercel/og`)

7. **Codex CLI JSONL support**
   - Verify JSONL parser works with Codex output format
   - Wire and document alongside Claude Code hook

8. **Son-of-Anton animation states in `hook.js`**
   - 8 states, ~20 lines

   | SoA event | State |
   |---|---|
   | Plan approved | `hyped` |
   | Ticket started / worktree entered | `focused` |
   | CI polling | `nervous` |
   | Subagent review running | `waiting` |
   | PR merged | `celebrating` + loot drop |
   | Phase closeout | `ascended` |
   | Codex rescue invoked | `calling_for_backup` |
   | Hook failure / verify red | `panicking` |

9. **`curl | bash` install script**

10. **README with GIF** (loot drop notification + armory profile screenshot)

11. **Deploy: Vercel + Convex cloud**

---

## Decisions Locked

| Question | Answer |
|---|---|
| Health system in Phase 1 | Engine only (silent). Web UI in Phase 2 |
| Codex CLI support | Yes — ship in Phase 1 |
| SoA animation states | Yes — ship in Phase 1 |
| Pet preview | Static placeholder. Live codex-pets API in Phase 3 |
| Domain | `codogotchi.pro` (also grab `codogotchi.app` as redirect) |
| `enrichPRQuality()` rate limit | ~~Cap to last 90 days **or** last 20 PRs on first sync~~ **Superseded:** forward-only from install ([`phase-01-as-shipped-delta.md`](../plans/phase-01-as-shipped-delta.md)) |

---

## Explicitly Deferred

- HP bar / health state on web (Phase 2)
- Death tombstone, ghost indicator on leaderboard (Phase 2)
- Friends system (Phase 2)
- Achievement badges UI (Phase 2)
- Full loot table expansion (Phase 2)
- Live pet preview from codex-pets API (Phase 3)
- Pet selection UI (Phase 3)
- Discord bot, guild system (Phase 3+)

---

## Reference Artifacts

Read in this order before touching any code:

1. `notes/private/session-summary-may-2026.md` — product context, what's built, open questions
2. `notes/private/stack-decisions-may-2026.md` — architecture and technology choices
3. `notes/private/ideation-storm-may-2026.md` — broader ideas, not binding

Scaffold to use as starting point: `notes/private/code/scaffold-v2/`

---

## Next Step

`/soa plan docs/product/drafts/phase-1-cli-armory.md`
