# Codogotchi Phase 05–14 Roadmap Index

_Drafted: 2026-05-27_
_Updated: 2026-06-02 — Phase 09 bumped to extended platform hooks; RPG ladder shifted 09→10 … 13→14_
_Status: Draft index for `/soa ideate` output — not a product plan_
_Prior shipped: Phase 01–04 ([phase-04-floating-pet.md](../plans/phase-04-floating-pet.md))_

---

## Distribution model

**Codogotchi ships as a notarized DMG — not Mac App Store.** This is the permanent model for v1, not a stopgap. The hook pipeline writes to agent config dirs and spawns `codogotchi-hook` on lifecycle events; App Store sandboxing is incompatible with the core value prop. The target audience (AI developers) expects and trusts direct distribution.

| Channel | Status |
| --- | --- |
| **GitHub Releases + notarized DMG** | Primary |
| **Sparkle** (auto-update) | Phase 08+ |
| **`brew install --cask`** | Optional alongside GitHub Releases |
| **Mac App Store** | Not v1 — revisit only if non-developer discovery becomes a strategic priority |

**Distribution milestone:** Phase 08 (CLI bundling inside `Contents/MacOS/`) closes the DMG story. After that the `.app` is a fully self-contained drag-and-drop artifact with no PATH prerequisite. See local operator notes: `notes/private/codogotchi-distribution-and-monetization-stance.md` (not in public repo).

---

## Product model

| Mode | Default | Unlock |
| --- | --- | --- |
| **Lite** | `codogotchi hooks install` + app | Native Codex-class pet; multi-platform hooks; SoA gates; no Convex required |
| **Alive (RPG)** | Opt-in | Settings **Turn on alive pet** or `codogotchi enroll` — XP, health, loot, sync |

---

## Phase ladder

| Phase | Draft | Repo | RPG? |
| --- | --- | --- | --- |
| **05** | [phase-05-lite-install-and-onboarding.md](./phase-05-lite-install-and-onboarding.md) | codogotchi | Lite default |
| **06** | [phase-06-platform-parity-and-attention.md](./phase-06-platform-parity-and-attention.md) | codogotchi | Lite |
| **07** | [phase-07-signal-honesty-and-soa-global-gates.md](./phase-07-signal-honesty-and-soa-global-gates.md) | codogotchi + **SoA upstream** | Lite |
| **08** ⭐ | [phase-08-settings-window-and-observability.md](./phase-08-settings-window-and-observability.md) | codogotchi | Both — **lite v1 release gate** |
| **09** | [phase-09-extended-platform-hooks.md](./phase-09-extended-platform-hooks.md) ([plan](../plans/phase-09-extended-platform-hooks.md)) | codogotchi | Lite — **next phase** |
| **10** | [phase-10-floating-progression-hud.md](./phase-10-floating-progression-hud.md) | codogotchi | Alive only |
| **11** | [phase-11-health-visuals-and-decay.md](./phase-11-health-visuals-and-decay.md) | codogotchi | Alive only |
| **12** | [phase-12-level-curve-100-and-migration.md](./phase-12-level-curve-100-and-migration.md) | codogotchi | Alive |
| **13** | [phase-13-loot-equip-companion-and-custom-pets.md](./phase-13-loot-equip-companion-and-custom-pets.md) | codogotchi | Alive + premium |
| **14** | [phase-14-premium-soa-animation-pack.md](./phase-14-premium-soa-animation-pack.md) | codogotchi | Premium |

**Son-of-Anton upstream (tracked in Phase 07 draft):** SoA writes directly to `~/.codogotchi/state.json` on gate emit — no intermediate `gate-events.ndjson` file. Plan separately in son-of-anton repo.

---

## Superseded / long-horizon

- [phase-2-social-health-drama.md](./phase-2-social-health-drama.md) — web armory, friends, leaderboard (not current ladder)
- [phase-1-cli-armory.md](./phase-1-cli-armory.md) — public launch vision
- [codogotchi-phase-04-05-roadmap.md](../../notes/public/codogotchi-phase-04-05-roadmap.md) — pre–Phase 04 ladder; SoA hook hardening folded into 06/07

---

## Suggested plan order

1. ✅ **05** lite install + onboarding
2. **06** → **07** platform parity + SoA signal honesty (lite critical path)
3. **08** settings window + CLI bundling — **lite v1 release gate**
4. **09** extended platform hooks — [product plan](../plans/phase-09-extended-platform-hooks.md) written; approve then `/soa decompose`
5. **10–11** RPG HUD + health visuals (alive mode)
6. **12–14** monetization stack (level curve, loot, premium animation pack)

---

## Field finding (2026-05-27) — Cursor without `~/.cursor/hooks.json`

Dogfooding confirmed: the pet animates during **Cursor Agent** sessions even when `~/.cursor/hooks.json` has no Codogotchi entries. Cursor loads **Claude Code–compatible** hooks from `~/.claude/settings.json` when **Settings → Features → Third-party skills** is enabled ([Cursor third-party hooks](https://cursor.com/docs/reference/third-party-hooks)). `codogotchi setup` / `hooks install` wires `codogotchi-hook` there (and in `~/.codex/hooks.json`), not in Cursor’s native hooks file. Transition logs then show `source_origin: "claude_code"` and Cursor tool names (`Shell`, `Grep`, …) — a **mis-label**, not proof the event came from the Claude Code app. Phase **06** makes attribution honest and adds a native `~/.cursor/hooks.json` installer; Phases **05** and **08** should document the bridge for lite onboarding and debugging. Phase **09** extends the same native-install pattern to **Copilot** (which also reads `.claude/settings.json`).

---

## Spritesheet architecture (decided 2026-05-28)

Three-tier model. See [phase-06-animation-and-signal-research.md](../../notes/public/phase-06-animation-and-signal-research.md) for full spec.

| Tier | File | Unlock | Linked to |
|---|---|---|---|
| 1 | `spritesheet.webp` (Codex-compatible) | Import Pet (Settings) | Nothing — Codex vocabulary, codogotchi trigger semantics |
| 2 | `codogotchi-lite-spritesheet.webp` | Ships with default pets; BYO | Hook heuristics — thinking/implementing/testing, richer idle |
| 3 | `codogotchi-soa-spritesheet.webp` | SoA opt-in / premium | SoA gate events |
| 4 | `codogotchi-rpg-spritesheet.webp` | RPG alive mode (Convex enroll) | RPG milestones — level-up, evolution, loot, health decay |

**Default pets at v1:** 3 pets (all spritesheets made by owner). Development continues with **Maew** only until v1.

**`requesting_input` renamed `standby`** (Phase 06): agent finished turn, ready for next prompt. Distinct from `idle` (no agent context).

---

## Research links

- Ideation storm — `notes/private/codogotchi-ideation-storm-roadmap-draft.md` (operator-local)
- [Native Codex parity](../../notes/public/codogotchi-native-codex-pet-feature-parity-roadmap.md)
- [Platform / signal pipeline](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md)
- [SoA alignment](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md)
