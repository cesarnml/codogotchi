# Codogotchi Phase 05–14 Roadmap Index

_Drafted: 2026-05-27_
_Status: Draft index for `/soa ideate` output — not a product plan_
_Prior shipped: Phase 01–04 ([phase-04-floating-pet.md](../plans/phase-04-floating-pet.md))_

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
| **08** | [phase-08-floating-progression-hud.md](./phase-08-floating-progression-hud.md) | codogotchi | Alive only |
| **09** | [phase-09-health-visuals-and-decay.md](./phase-09-health-visuals-and-decay.md) | codogotchi | Alive only |
| **10** | [phase-10-settings-window-and-observability.md](./phase-10-settings-window-and-observability.md) | codogotchi | Both (RPG unlock) |
| **11** | [phase-11-level-curve-100-and-migration.md](./phase-11-level-curve-100-and-migration.md) | codogotchi | Alive |
| **12** | [phase-12-loot-equip-companion-and-custom-pets.md](./phase-12-loot-equip-companion-and-custom-pets.md) | codogotchi | Alive + premium |
| **13** | [phase-13-premium-soa-animation-pack.md](./phase-13-premium-soa-animation-pack.md) | codogotchi | Premium |
| **14** | [phase-14-extended-platform-hooks.md](./phase-14-extended-platform-hooks.md) | codogotchi | Lite |

**Son-of-Anton upstream (tracked in Phase 07 draft):** direct write to `~/.codogotchi/gate-events.ndjson` when `codogotchi.enabled` — plan separately in son-of-anton repo.

---

## Superseded / long-horizon

- [phase-2-social-health-drama.md](./phase-2-social-health-drama.md) — web armory, friends, leaderboard (not current ladder)
- [phase-1-cli-armory.md](./phase-1-cli-armory.md) — public launch vision
- [codogotchi-phase-04-05-roadmap.md](../../notes/public/codogotchi-phase-04-05-roadmap.md) — pre–Phase 04 ladder; SoA hook hardening folded into 06/07

---

## Suggested plan order

1. `/soa plan` **05** → **06** (lite path + parity)
2. **07** in parallel with SoA upstream global gate phase
3. **10** early if Settings unlock is priority; else **08–09** after enroll story is clear
4. **11–13** monetization stack; **14** when fixtures exist

---

## Field finding (2026-05-27) — Cursor without `~/.cursor/hooks.json`

Dogfooding confirmed: the pet animates during **Cursor Agent** sessions even when `~/.cursor/hooks.json` has no Codogotchi entries. Cursor loads **Claude Code–compatible** hooks from `~/.claude/settings.json` when **Settings → Features → Third-party skills** is enabled ([Cursor third-party hooks](https://cursor.com/docs/reference/third-party-hooks)). `codogotchi setup` / `hooks install` wires `codogotchi-hook` there (and in `~/.codex/hooks.json`), not in Cursor’s native hooks file. Transition logs then show `source_origin: "claude_code"` and Cursor tool names (`Shell`, `Grep`, …) — a **mis-label**, not proof the event came from the Claude Code app. Phase **06** makes attribution honest and adds a native `~/.cursor/hooks.json` installer; Phases **05** and **10** should document the bridge for lite onboarding and debugging.

---

## Research links

- [Ideation storm](../../notes/public/codogotchi-ideation-storm-roadmap-draft.md)
- [Native Codex parity](../../notes/public/codogotchi-native-codex-pet-feature-parity-roadmap.md)
- [Platform / signal pipeline](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md)
- [SoA alignment](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md)
