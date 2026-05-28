# OpenPets — Competitive Analysis

_Research date: 2026-05-28_
_Sources: https://github.com/alvinunreal/openpets, https://openpets.dev_

---

## TL;DR

Your read is essentially correct: **Codex pets for any agent platform** is the core thesis. But that undersells two genuine additions — a 1090+ pet community catalog and a first-party plugin system for non-agent ambient behaviors. OpenPets is going wide and shallow; codogotchi is going narrow and deep. These are compatible bets for now.

---

## Vital Stats

| Stat | Value |
|---|---|
| Created | 2026-05-04 (24 days ago) |
| Stars | 958 (approaching 1000 in under a month) |
| Forks | 33 |
| Releases | 14 releases in 24 days |
| Contributors | Essentially 1 (alvinunreal: 118 commits; everyone else ≤1) |
| Language | TypeScript (Electron + pnpm monorepo) |
| License | MIT |
| Author org | **Boring Dystopia Development** — alvinunreal on X |

---

## Architecture

### Stack
- **Desktop app:** Electron — not native. TypeScript + Vite + Tailwind on the renderer side, pnpm workspace monorepo.
- **Cross-platform from day 1:** macOS arm64 + x64, Windows x64, Linux AppImage. Electron is the unlock here.
- **Currently unsigned** — macOS Gatekeeper warning required, `xattr -dr com.apple.quarantine` in the README. No notarization yet.

### Monorepo packages
```
packages/
  mcp/         — MCP server (the primary integration surface)
  agent-events/ — shared hook speech validation
  claude/      — Claude Code hooks + hook messages
  cursor/      — Cursor MCP + rules integration
  opencode/    — OpenCode plugin
  pi/          — Pi agent
  client/      — IPC client connecting packages to desktop app
  install-pet/ — pet installation helpers
  pet-format/  — pet format spec marker (thin)
  cli/         — CLI entry points
plugins/
  official/    — 7 bundled plugins (v2.5+)
apps/
  desktop/     — Electron app (control center + pet window)
```

### How it actually works

**Integration model: MCP-first, hooks secondary.**

1. The desktop app runs a local IPC server (not HTTP — it's Electron IPC via a named socket/pipe).
2. `@open-pets/mcp` wraps that IPC server as an MCP stdio server, exposing three tools to any MCP-capable agent:
   - `openpets_status` — is the pet running, which pet is active
   - `openpets_say` — show a speech bubble (validated: max 140 chars, no code, no URLs/paths, no secrets)
   - `openpets_react` — trigger a reaction animation
3. Claude Code hooks (secondary layer) passively fire on lifecycle events and call the same IPC client — but with **static, throttled speech** only. No dynamic content from hooks. Hard-coded `HookSpeechCategory` buckets. 20s speech cooldown, 10s reaction cooldown.
4. Cursor integration uses Cursor MCP + `.cursorrules` injection.

**Hook events mapped (Claude):** `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure` — but the reaction is a simple category pick from static phrases, not signal-based classification.

**The "skill" install mechanism:**
```bash
npx skills add alvinunreal/openpets --skill openpets
```
Uses `skills.sh` — a skill package manager. You then tell your agent in natural language to install it. The AI does the setup. Clever distribution.

---

## Release History (velocity tells the story)

| Date | Version | What shipped |
|---|---|---|
| 2026-05-04 | v0.1.0 | Initial prerelease |
| 2026-05-05 | v0.1.1 | Patch |
| 2026-05-06 | v0.1.2–v0.1.3 | Two patches in one day |
| 2026-05-10 | v2.0.0 | Major jump — Electron desktop app, multi-platform DMG/exe/AppImage |
| 2026-05-12–17 | v2.0.5–v2.0.9 | Daily patches, MCP stabilization |
| 2026-05-20 | v2.1.0–v2.1.1 | Integrations screen in settings |
| 2026-05-24 | v2.1.2 | Fix pass |
| 2026-05-27 | v2.5.0 | **Plugin platform launch** — 7 bundled plugins |
| Active today | — | MCP lease retry backoff (PR #35) |

**Interpretation:** v0.1→v2.0 was a 6-day complete rebuild into Electron. v2.5 introduced the plugin platform as a strategic pivot. This is a solo developer moving extremely fast, likely with heavy AI assistance (there's an `AGENTS.md` in the repo).

---

## Feature Set

### What it actually does
- Desktop pet (sprite-based, Codex spritesheet format) sitting in a floating window
- Tray/menubar icon
- **React to agent events** via MCP or hooks — animations + static speech bubbles
- **1090+ pet catalog** on openpets.dev — community submissions, browsable and importable from the app
- **Pet routing** — assign different pets to different agent sessions/projects

### Plugin system (v2.5 — the pivot)
First-party plugins that run independently of any agent:
- **Ambient Companion** — idle check-ins, ambient moments
- **Break Buddy** — stretch/hydrate/rest reminders
- **Pet Pal** — playful pet actions, quick interactions
- **Focus Buddy** — passive focus-session timer controls
- **Wander Buddy** — "safe little walks" (pet wanders the desktop)
- **Quick Reminders** — reminder system
- **GitHub Notifications** — (notable: non-agent notification integration)

This is a deliberate move away from pure agent-reaction toward an always-alive desktop companion that doesn't require any agent to feel useful.

### MCP tools exposed to agents
```
openpets_status  → is app running, which pet, why unavailable
openpets_say     → "hello, I'm thinking..." (140 char, static, validated)
openpets_react   → trigger animation reaction
```
The `say` validation is worth noting: it explicitly blocks code patterns, URLs, paths, and secret-like strings. Privacy-conscious by design — the speech bubble never leaks your work.

---

## What It's Missing (the signal gap)

OpenPets hooks observe **that** the agent did something, not **what** it did. There is no:

- Tool classification (`Edit` vs `Bash` vs `Read`)
- Command inspection (grep vs git push vs test runner)
- State machine (implementing vs reviewing vs running-tests)
- TTL / decay (no stuck-waving problem exists because reactions are ephemeral, not states)
- Delivery lifecycle awareness (no SoA gates, no ticket lifecycle)
- Attention contract (no "why does the pet want you" signal)

The reactions are effectively: `agent_started | agent_did_something | agent_stopped | agent_failed`. That's the full signal vocabulary. It's appropriate for the vibes use case — users who want a cute reaction don't need more — but it's not useful as a productivity signal layer.

---

## Distribution Model

- GitHub Releases primary — unsigned Electron app
- No auto-update yet (no Sparkle / Electron-updater appears wired)
- No Mac App Store (Electron IPC + external processes incompatible, same reason as codogotchi's DMG-only stance)
- `npx skills add` as the agent-assisted installer is genuinely clever — low-friction for the target audience

---

## Where They're Going

The plugin system launch (v2.5, 3 weeks in) is the clearest signal. They are:

1. **De-emphasizing agent dependency** — the pet works and feels alive without any agent configured
2. **Broadening the use case** — break reminders, focus timers, GitHub notifications are productivity tools, not just vibes
3. **Building a plugin ecosystem** — the `skills/` directory and plugin SDK suggest they want third-party plugins
4. **Cross-platform** — Windows/Linux users are a real audience for agent tools, and OpenPets serves them. Codogotchi explicitly doesn't.

The trajectory: **general desktop companion platform that optionally connects to AI agents**, not "AI agent pet." This is a deliberate pivot from the Codex-pet-clone starting point.

---

## On the "why are all my competitors Chinese" observation

`alvinunreal` is the author. `youngYangtze` is a contributor name. The pixel art pet aesthetic, the extremely fast solo shipping cadence, the Tamagotchi-adjacent product category — all consistent with a pattern of indie developers in China who picked up on the Codex pet phenomenon early and moved fast. `codexpet.xyz` (the Codex native pet catalog that spawned the spritesheet format) is also from this community. The format hegemony — everyone using the same 8×9 Codex spritesheet — is a direct result of them setting the standard first.

---

## Codogotchi vs OpenPets

| Dimension | OpenPets | Codogotchi |
|---|---|---|
| **Architecture** | Electron (TypeScript) | Swift/macOS native |
| **Platform** | macOS + Windows + Linux | macOS only |
| **Integration model** | MCP-first → agent drives pet | Hooks-first → passive observation |
| **Signal intelligence** | Low — "agent did X" category | High — what tool, what command, what state |
| **State machine** | Reactions (ephemeral) | Named activity states with transitions |
| **TTL / decay** | Not needed (reactions are instant) | Core feature — stuck-waving fix |
| **SoA integration** | None | Deep — full delivery lifecycle gates |
| **Attention UX** | Static speech bubbles | Bubble + reason_kind + TTL + focus action |
| **Animation vocabulary** | Codex rows only | Codex + codogotchi-lite + SoA + RPG sheets |
| **Pet catalog** | 1090+ community pets | 1 (Maew) — 3 planned for v1 |
| **Plugin system** | Yes (v2.5) — ambient behaviors | Not yet (future phases) |
| **Distribution** | Unsigned Electron | Notarized DMG (Phase 08) |
| **Business model** | Free/OSS forever | Free lite / paid alive |
| **RPG/progression** | None | Full XP/HP/loot system (alive mode) |
| **Development pace** | 14 releases in 24 days | Slower, deeper, SoA-orchestrated |
| **Team size** | ~1 person | 1 person |

### Where OpenPets wins
- **Cross-platform** — serves Windows/Linux users codogotchi doesn't reach
- **Pet catalog breadth** — 1090+ is a massive social moat; codogotchi ships 3
- **Time to first pet** — download, no agent required, pet is alive via plugins immediately
- **MCP-native** — any MCP-capable agent can drive it without hooks; forward-compatible
- **Plugin ecosystem potential** — non-agent ambient behaviors are a real product category

### Where Codogotchi wins
- **Signal fidelity** — codogotchi knows *what* the agent is doing; OpenPets knows *that* it did something
- **Delivery lifecycle** — SoA gate animations reflect actual ticket progress, not just "agent active"
- **Attention UX** — the bubble has a reason, an expiry, a focus action; OpenPets speech is static
- **macOS native** — lower memory, no Electron overhead, notarized distribution
- **RPG depth** — XP, HP, loot, alive mode is a retention/monetization layer OpenPets explicitly doesn't have
- **No "agent cooperation required"** — passive hook observation works even when the agent ignores you; MCP-first requires the agent to call the tools

### The real question
Are these competing for the same users? Largely no, right now:

- A casual Cursor or VS Code user who wants a cute pet that reacts → **OpenPets** (cross-platform, 1090+ pets, works immediately)
- A developer deep in SoA-orchestrated delivery who wants their pet to mirror their delivery lifecycle → **codogotchi** (no contest, OpenPets doesn't speak this language)
- A Claude Code power user on macOS who wants the richest signal experience → **codogotchi**
- A Windows developer who wants any desktop pet at all → **OpenPets** (codogotchi doesn't exist for them)

The risk scenario: OpenPets adds signal intelligence and SoA awareness. Given the shipping velocity, this is possible within weeks. But signal fidelity requires understanding what hooks actually contain, and their current privacy-first "no dynamic content" design is architecturally opposed to it.

---

## One thing to watch

Their `openpets_say` MCP tool with privacy guards is actually a smart design pattern that codogotchi doesn't have an equivalent of: **the agent can explicitly annotate the pet's bubble.** When Claude finishes a hard task it can say "Done, all tests pass" and the pet says it. This is a different contract than codogotchi's passive state inference — it's cooperative rather than observational. For users who want their agent to narrate its own work, that's compelling even if the signal vocabulary is shallower.

The answer isn't to copy it — codogotchi's passive observation model is more honest and doesn't require agent cooperation. But worth knowing it exists as a use case.
