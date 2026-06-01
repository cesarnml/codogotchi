# OpenPets — Competitive Analysis

_Research date: 2026-05-28 — hands-on session: 2026-06-01_
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
- **Cross-platform** — serves Windows/Linux users codogotchi doesn't reach *(caveat below)*
- **Pet catalog breadth** — 1090+ is a massive social moat; codogotchi ships 3
- **Time to first pet** — download, no agent required, pet is alive via plugins immediately
- **MCP-native** — any MCP-capable agent can drive it without hooks; forward-compatible
- **Plugin ecosystem potential** — non-agent ambient behaviors are a real product category

**Caveat on cross-platform:** Mac users pay for premium software; Windows/Android users largely don't — this is the App Store vs Play Store monetization reality. Codogotchi's initial target market is Mac-native developers. Cross-platform reach expands the audience but doesn't expand the paying audience at v1. OpenPets' Windows/Linux users are real users who won't be paying customers for a premium alive-mode tier. The macOS-only bet is a deliberate monetization alignment, not a gap.

### Where Codogotchi wins
- **Signal fidelity** — codogotchi knows *what* the agent is doing; OpenPets knows *that* it did something
- **Delivery lifecycle** — SoA gate animations reflect actual ticket progress, not just "agent active"
- **Attention UX** — the bubble has a reason, an expiry, a focus action; OpenPets speech is static
- **macOS native** — lower memory, no Electron overhead, notarized distribution
- **RPG depth** — XP, HP, loot, alive mode is a retention/monetization layer OpenPets explicitly doesn't have
- **Token-neutral** — hooks fire on lifecycle events outside the agent's context window; zero tokens, always on. OpenPets' MCP-first model means every `openpets_say`/`openpets_react` call burns tokens for the invocation + response + whatever the agent spent deciding to call it. The pet only reacts when the agent chooses to spend on it. Codogotchi's pet always reflects what the agent is doing, for free.
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

---

## Resource Usage Benchmark — 2026-06-01

_Methodology: `ps %cpu` sampled every 5s over 60s for idle; every 2s over 16s for active animation. Memory via `vmmap -summary` physical footprint per process. Machine: MacBook Pro Apple Silicon, macOS. Both apps running simultaneously with default installed plugins._

### Memory

| | Codogotchi | OpenPets |
|---|---|---|
| **Processes** | 1 | 10 |
| **Physical footprint** | **34.2 MB** | **312.8 MB** |
| **Ratio** | 1× | **9.1×** |

OpenPets process breakdown:
- Main process: 76.1 MB
- GPU process (Chromium): 98.9 MB
- Main renderer: 44.4 MB
- Utility helper: 7.4 MB
- Plugin sandbox renderers ×6: 14.2–14.4 MB each (~86 MB total)

The 6 plugin sandbox renderers are idle — zero CPU — but each costs ~14 MB simply to exist as an isolated Electron BrowserWindow. This is the plugin architecture tax.

### CPU

| | Codogotchi | OpenPets |
|---|---|---|
| **Idle — 60s average** | **2.8%** | **11.9%** |
| **Idle ratio** | 1× | **4.3×** |
| **Active animation — average** | **2.2%** | **41.5%** |
| **Active ratio** | 1× | **~19×** |

OpenPets active animation breakdown:
- Chromium GPU compositor: ~30% (sprite animation via CSS/canvas in the GPU process)
- Main renderer: ~10-11%
- Everything else: ~0%

**The GPU process is the entire story.** Chromium must composite every animation frame through its full GPU pipeline. Codogotchi shows no measurable CPU increase during animation — the GPU handles the sprite loop natively with no CPU involvement once loaded.

**The two OpenPets CPU states:** idle animation (~12%) vs reaction-triggered animation (~41%). The difference is the Chromium GPU process spinning up from 3-4% to 30-35% when a new reaction fires. It remains elevated for the full reaction duration before settling back.

### What's safe to claim on the marketing page (all measured)

- **"9× less memory"** — 34 MB vs 313 MB, measured via vmmap
- **"4× less CPU at idle"** — 2.8% vs 11.9%, 60-second average
- **"Up to 19× less CPU during active agent sessions"** — 2.2% vs 41.5%, measured while both pets were animating
- **"Single process"** — 1 vs 10, verified
- **"34 MB vs 313 MB"** — exact vmmap numbers

### Why the gap is structural, not tunable

OpenPets cannot close this gap without abandoning Electron. The Chromium GPU compositor is not optional — it's how Electron renders anything on screen. Every frame of sprite animation goes through: JavaScript → Chromium renderer → Chromium GPU process → Metal/GPU. Codogotchi's path is: SpriteKit → Metal. The intermediate layers are the cost.

The plugin sandbox memory cost (6 × ~14 MB) is similarly structural — isolated BrowserWindow renderers are Electron's only safe sandboxing primitive. It's the right security call; the cost is real.

---

## Hands-On Findings — 2026-06-01

Full install and integration session against v2.5.0 on macOS (Apple Silicon). Findings below are from direct observation, not docs.

### Installation friction

The Integrations panel writes the Claude MCP config with a **lowercase path** (`/Applications/openpets.app/`) but macOS places the app at `/Applications/OpenPets.app/`. On a case-sensitive FS this would be a hard failure; on standard macOS HFS+ it silently "works" for `openpets_status` (which only checks the IPC socket file) but fails for `openpets_say` and `openpets_react` with `"IPC lease unavailable"` — the MCP server process never fully starts. The misleading error makes it look like an IPC timing issue, not an install bug. Took significant debugging to identify.

**Codogotchi implication:** our install path must be verified and exercised end-to-end in CI. A silent partial install is worse than a hard failure.

### IPC architecture

The desktop app publishes a socket at `/tmp/openpets-<uid>/openpets-<pid>.sock` with a JSON lease file at `~/Library/Application Support/OpenPets/runtime/ipc.json`. The MCP server connects to this socket. The `openpets_status` tool reads the ipc.json and reports `leaseActive` — but this can return `true` even when the MCP server failed to start, because it reads the file rather than probing the socket. Two-phase availability check with a single-phase status report.

### Hook lifecycle — what actually fires and what doesn't

Validated against live hooks. The full event list is: `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`.

Reaction mappings (from source):
- `UserPromptSubmit` → `thinking`
- `PreToolUse` + Edit/Write/MultiEdit → `editing`
- `PreToolUse` + Bash matching test runner pattern → `testing`
- `PreToolUse` + anything else → **no reaction** (returns `undefined`)
- `PermissionRequest` → `waiting` + throttled speech
- `Notification` → **nothing** (wired but no-op, reserved for future)
- `Stop` → `success`
- `StopFailure` → `error` + throttled speech

**Key finding:** most `PreToolUse` events (Read, Bash non-test, etc.) produce no reaction at all. The pet is idle for the majority of a real session. Only file-write and test-run events animate her. In practice the pet looks almost completely static during normal work — same as the "native Codex pet" behavior the user complained about before the hooks were wired.

### Throttle behavior

Speech cooldown: 20 seconds. Reaction cooldown: 10 seconds. Both implemented via a JSON file at `$XDG_STATE_HOME/openpets/claude-hook-throttle.json`. Hooks always return exit 0 (never block Claude). Throttle is best-effort — write failures are silently ignored.

The 10s reaction cooldown means that in a fast editing session (multiple Edit calls per second), only the first one animates. She goes idle immediately after.

### Speech bubble UX — confirmed gap

Chat bubbles have no interactivity. Clicking a speech bubble does nothing — no focus on originating app, no dismiss affordance, no action surface. This applies to both MCP-triggered `openpets_say` messages and hook-triggered speech. The "attention" speech category (PermissionRequest) appears identically to a normal speech event from the user's perspective — there is no visual distinction between "I want to tell you something" and "I need you to do something."

**Codogotchi advantage this confirms:** our `reason_kind` + focus action + TTL contract is meaningfully differentiated. OpenPets has no equivalent of a bubble that knows why it exists or expires when ignored.

### Global vs project-local hooks

The official install path (`configure --agent claude`) writes project-local `settings.local.json` hooks using `npx -y @open-pets/cli@<version>`. There is no global hook install option from the UI. Users who want Maew to react across all projects must manually add global hooks to `~/.claude/settings.json` — the app does not guide this. The Integrations panel "Installed" badge reflects MCP config only, not hook install status.

**Codogotchi implication:** `codogotchi hooks install` writing to `~/.claude/settings.json` (global, always-on) is a better default UX than per-project opt-in.

### Codex support

Not supported. `openpets configure --agent codex` returns `Unsupported agent: codex`. The supported list is `claude`, `opencode`, `cursor`. Despite the product's origin as a "Codex pets for all agents" concept, Codex is not a first-class integration target.

---

## Deep Docs Research — 2026-06-01

_Source: openpets.dev/docs + full repo doc audit (docs/*, DESIGN.md, plugins.md, claude-integration.md, mapping.md)_

### Complete reaction vocabulary

OpenPets accepts 11 reactions mapped to 9 spritesheet rows:

| Reaction | Row | Animation | Trigger |
|---|---|---|---|
| `idle` | 0 | Slow 5500ms loop | Default state |
| `running-right` | 1 | Drag motion | Pet drag only |
| `running-left` | 2 | Drag motion | Pet drag only |
| `waving` | 3 | 2-loop one-shot | `Notification` hook, `waving` |
| `success` / `celebrating` | 4 | 2-loop one-shot (`jumping`) | `Stop`, manual |
| `error` | 5 | 2-loop one-shot (`failed`) | `StopFailure` |
| `waiting` / `testing` | 6 | Looping | `PermissionRequest`, test commands |
| `working` / `editing` / `running` | 7 | Looping | Tool use, Bash, file edits |
| `thinking` | 8 | Looping (`review`) | `UserPromptSubmit` |

`celebrating` exists as an allowed MCP reaction but is **never emitted by hooks** — it's manual/MCP only.

### Corrected Claude hook mapping (vs. our earlier analysis)

The hooks doc reveals our earlier analysis was incomplete — hooks map more richly than we found in the source:

| Event | Condition | Reaction | Speaks? |
|---|---|---|---|
| `UserPromptSubmit` | Any | `thinking` | Yes, 20s cooldown |
| `PreToolUse` | Edit/Write/MultiEdit | `editing` | No |
| `PreToolUse` | Bash + test pattern | `testing` | No |
| `PreToolUse` | **Bash + non-test** | **`running`** | No |
| `PreToolUse` | **Any other tool** | **`working`** | No |
| `PermissionRequest` | Any | `waiting` | Yes, 3s cooldown |
| `Notification` | Any | **`waving`** | No |
| `Stop` | Any | `success` | Yes, 20s cooldown |
| `StopFailure` | Any | `error` | Yes, 20s cooldown |

**Correction to our earlier notes:** `PreToolUse` on non-test Bash maps to `running` (not nothing), and any other tool maps to `working` (not nothing). The pet is more active than we concluded from source inspection. Our live observation of near-constant idle was correct but the cause was the **10s reaction throttle**, not missing mappings.

### MCP memory instructions system

OpenPets writes two managed files into Claude's memory layer:
- `~/.claude/CLAUDE.md` — receives a managed `@~/.claude/openpets.md` import block
- `~/.claude/openpets.md` — contains the instructions for when/how Claude uses the tools

This is a first-class install surface. Removing the MCP entry does not remove the memory instructions — they must be uninstalled separately. Our hands-on install did not include this (the Integrations panel may have written it — worth checking).

### Plugin system — full SDK surface

The plugin SDK is more capable than the public docs suggest:

```ts
ctx.pet.speak(message)          // speech bubble
ctx.pet.react(reaction)         // animation
ctx.pet.moveBy({ x, y, durationMs })   // bounded movement
ctx.pet.wander({ distance, durationMs })
ctx.pet.moveToHome()
ctx.schedule.once/every/daily/cancel
ctx.storage.get/set/delete      // per-plugin persisted JSON
ctx.config.get / onChange       // host-rendered config schema
ctx.commands.register           // tray right-click commands with optional forms
ctx.status.set({ text, tone })  // status line in Plugins UI
ctx.http.fetch                  // GET-only, HTTPS, host-allowlisted, response-capped
ctx.log.debug/info/warn/error
```

Plugins run in sandboxed Electron hidden renderer windows (`nodeIntegration: false`, `sandbox: true`, unique non-persistent partition). Each plugin gets its own isolated window. All SDK calls cross validated IPC to main process.

**Capabilities that stand out:**
- `pet:move` — plugins can physically move the pet on screen (Wander Buddy uses this)
- `commands` + forms — plugins can register right-click commands with typed form inputs (Quick Reminders uses this to let users set reminders from the tray)
- `network` — proxied GET-only HTTPS through the app's HTTP proxy with host allowlisting
- `config.onChange` — react to live config changes without restart

**Hard limits:** GET-only HTTP, no POST/webhooks, no OAuth, no token storage, no private GitHub, no arbitrary executables, no Node APIs, no filesystem.

### Bubble display system

| Scenario | What appears in bubble |
|---|---|
| `openpets_react("testing")` | Randomized pool text: "Running the checks" |
| `openpets_say("Done")` | "Done" (message wins over pool text) |
| `openpets_say("Done", reaction: "success")` | "Done" (message wins, but success animation plays) |

Bubble durations: 4s default, 5s for success/error, up to 12s for longer messages (length-aware). Bubbles have **no click target, no dismiss affordance, no action affordance** — confirmed in source (`createBubbleMarkup` in `pet-window.ts`).

### IPC lease system

Leases are how OpenPets routes events to specific pet windows. Lease TTL: 15 seconds. Heartbeat interval: 5 seconds. When the last lease for an explicit pet expires, that agent window closes. Hooks acquire a short-lived lease per-event with no long-running connection.

The IPC protocol rotates tokens on every app restart (32-byte random). Clients discover the socket and token via `~/Library/Application Support/OpenPets/runtime/ipc.json`.

### What's planned but not built

From `docs/plugins.md` future work section:
1. Calendar plugin (local/.ics before OAuth)
2. Local webhook/plugin for automation tools
3. More host-rendered config field types
4. Signed reviewed third-party plugin submissions
5. Plugin marketplace/search (after trust/review maturity)
6. OAuth/private GitHub support (after secure token storage)
7. A no-code rules UI for user-created automations

Third-party plugin marketplace is explicitly deferred until sandboxing and review processes mature.

---

## Feature Recommendations for Codogotchi

### 🔴 High Priority — Directly addresses gaps OpenPets cannot fill

#### 1. MCP-enriched AttentionBubble (session context on Stop)

**The problem:** OpenPets' `Stop` → `success` is a static "Done" / "All set" with no context. The user doesn't know *what* finished. Codogotchi's AttentionBubble has a `reason_kind` field but it's inferred passively from hook payloads — it doesn't know *what* the agent accomplished.

**The idea:** Wire a Codogotchi MCP tool (`codogotchi_attention`) that Claude calls at the end of meaningful work — not on every `Stop`, but when it has something worth reporting. Claude passes a structured payload:

```json
{
  "reason": "Phase 08 ticket 3 complete — 4 files changed, tests passing",
  "reason_kind": "completion",
  "session_id": "<current>",
  "urgency": "low"
}
```

The `Stop` hook fires passively as the animation trigger (zero tokens), and the MCP call enriches the bubble with actual context. The two layers cooperate: hook drives the animation, MCP drives the text.

**Result:** AttentionBubble becomes the only desktop pet bubble that tells you *why* it's showing and *what* finished. OpenPets has two ceilings here: (1) their **hooks are always static** — the hook binary picks from hard-coded message pools and can never carry dynamic content regardless of validation; (2) their **MCP `openpets_say` validation** rejects anything path-like, code-like, URL-like, or secret-like — so "ticket 3 done, tests passing" might pass, but "modified auth.ts, 4 files changed" or any actual output/filenames won't. More critically, neither path has `reason_kind`, urgency, reply affordance, or session routing — so even a clean summary is a display-only bubble with no behavior attached.

**Codogotchi advantage:** passive observation (hook) + cooperative enrichment (MCP) hybrid. Neither alone is as good as both together.

---

#### 2. Reply-to-thread from bubble

**The problem:** Every desktop pet bubble, including OpenPets', is a one-way channel. You see it, you dismiss it, you go find the terminal. There's no affordance for "respond to this."

**The idea:** When an AttentionBubble appears with `reason_kind: "input_needed"` or `"completion"`, show a small reply input. User types a response. Codogotchi injects it as the next prompt in the originating session.

This requires:
- Session tracking — the hook payload carries `CLAUDE_PROJECT_DIR` and `session_id`. Map these to the active Claude process.
- Prompt injection — use Claude Code's `--resume <session_id>` or equivalent to continue the thread.
- Reply affordance in the bubble UI — a small text field + send button, not a full window.

**Result:** The bubble becomes a lightweight command surface. "Tests failed" → user types "fix the flaky test" right in the bubble → Claude continues. OpenPets has no equivalent and their architecture makes it impossible (they explicitly block dynamic content from reaching speech, and have no session tracking at all).

---

#### 3. Focus button → jump to originating window ✅ Already shipped in Codogotchi

**This is not a recommendation — it is an existing codogotchi advantage to document and market.**

Codogotchi's AttentionBubble already implements Focus, routing to the originating session via the hook payload. OpenPets has no equivalent — confirmed hands-on, confirmed in source (`createBubbleMarkup` has no click handler). This is a genuine differentiator codogotchi already owns.

The competitive framing: "codogotchi bubbles know why they exist and take you there. OpenPets bubbles display text and disappear."

---

### 🟡 Medium Priority — Ecosystem / platform

#### 4. Plugin ecosystem (parity with OpenPets, with SoA-aware extensions)

OpenPets' plugin SDK is well-designed and worth matching. The core manifest + sandboxed JS runtime + capability permissions model is sound. Key differences to implement in Codogotchi:

**Match OpenPets:**
- Manifest v2 with declared permissions
- Sandboxed JS runner (same Electron pattern or equivalent for native app)
- SDK: `pet.speak`, `pet.react`, `schedule`, `storage`, `config`, `commands`, `status`, `http` (GET, host-allowlisted)
- Right-click command registration with optional forms
- Plugins UI in Control Center: install/enable/disable/configure/update

**Go beyond OpenPets — SoA-aware plugin API:**
```ts
// New in Codogotchi plugin SDK — not in OpenPets
ctx.delivery.onPhaseStart(handler)     // SoA phase began
ctx.delivery.onTicketComplete(handler) // SoA ticket done
ctx.delivery.onPRReady(handler)        // PR opened for review
ctx.delivery.onAgentBlocked(handler)   // agent needs human decision
ctx.pet.setActivityState(state)        // named states with TTL + decay
```

This makes Codogotchi plugins aware of the delivery lifecycle — something OpenPets plugins can never be because OpenPets has no delivery lifecycle concept at all.

**First-party plugins to ship:**
- **SoA Companion** — animates phase/ticket progress, celebrates merges (the Codogotchi-native equivalent of Ambient Companion)
- **Break Buddy** — same as OpenPets (table stakes)
- **Focus Buddy** — same as OpenPets (table stakes)
- **Quick Reminders** — same as OpenPets (table stakes)
- **Wander Buddy** — same as OpenPets (table stakes, Maew walks)
- **GitHub PRs** — private repo aware (vs OpenPets' public-only, no-OAuth limitation)
- **Daily Standup** — pet prompts you for your standup at 9am, sends to Slack/Linear (no equivalent in OpenPets)

---

#### 5. `codogotchi_attention` MCP tool (the full contract)

Beyond the enrichment use case above, define a proper MCP tool with a richer contract than OpenPets' 3-tool set:

```ts
codogotchi_attention({
  message: string,          // 1-140 chars, validated
  reason_kind: "completion" | "input_needed" | "blocked" | "review_ready" | "error",
  urgency: "low" | "medium" | "high",
  reply_enabled: boolean,   // enables the reply input affordance
  session_id?: string,      // for focus/reply routing
  ttl_seconds?: number      // bubble auto-expires, default 30
})

codogotchi_react({ reaction: string })   // matches OpenPets' openpets_react
codogotchi_status()                       // matches OpenPets' openpets_status
```

The `reason_kind` is the key differentiator — it drives the bubble's visual treatment, focus behavior, and whether the reply affordance appears. OpenPets has no `reason_kind` concept.

---

### 🟢 Lower priority — Catalog / distribution

#### 6. Pet catalog compatibility with openpets.dev

OpenPets uses the standard Codex spritesheet format (8×9 grid, same rows codogotchi uses). Their catalog at `openpets.dev/pets/catalog.v3.json` has 1090+ pets in that format.

Codogotchi should be able to install any OpenPets-compatible pet. The format is the same — the only delta is `pet.json` schema differences. Making Codogotchi read OpenPets-format `pet.json` gives instant access to 1090+ community pets. This is a **catalog moat we can borrow for free** by being format-compatible. Ship 3 native pets, support 1090+ via compatibility.

#### 7. Cursor hooks gap — don't wait for Cursor

OpenPets confirmed: Cursor has no lifecycle hooks API. Neither does any other non-Claude agent. Codogotchi is in the same position.

**Strategic response:** lean into Claude Code as the primary integration depth story. Cursor and others get MCP-only (cooperative model). Make the Claude story so compelling that it's a selling point — "works best with Claude Code" is fine if Claude Code is where your power users are.

---

## One thing to steal

**`npx skills add` as the install surface is genuinely clever distribution.** The user types one command, tells their agent to install it, and the AI does the wiring. Zero friction for the exact audience that already has an AI agent running. Codogotchi's current install is `codogotchi hooks install` which is fine — but a `npx skills add codogotchi` (or equivalent) wrapper that lets the agent self-install via natural language would be worth building for Phase 08 or the post-launch distribution push. The mechanic doesn't require the `skills.sh` ecosystem specifically — the pattern is: one-liner that the agent can run, agent handles the rest.
