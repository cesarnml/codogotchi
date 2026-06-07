# Codogotchi Phase 05–14 Roadmap Index

_Drafted: 2026-05-27_
_Updated: 2026-06-03 — Phase 10 (Free RPG tier) delivered; Lite retired as product floor; notarization next_
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
| **Free RPG (local)** | Shipped Phase 10 — hearts + 1–100 level + HUD (local only) | `features.rpg_enabled: true` (today still via `codogotchi rpg` or manual config); opt out HUD in **Settings → RPG** |
| **Animation-only (legacy Lite config)** | `features.rpg_enabled: false` | Hooks + floating pet animation; no local progression writer — **retired as product floor** |
| **Alive + sync** | Deferred (Phase 11+) | Opt-in leaderboard / Convex — not v1 |

---

## Phase ladder

| Phase | Draft | Repo | Status |
| --- | --- | --- | --- |
| **05** | [phase-05-lite-install-and-onboarding.md](./phase-05-lite-install-and-onboarding.md) | codogotchi | ✅ Shipped (historical Lite onboarding) |
| **06** | [phase-06-platform-parity-and-attention.md](./phase-06-platform-parity-and-attention.md) | codogotchi | ✅ Shipped |
| **07** | [phase-07-signal-honesty-and-soa-global-gates.md](./phase-07-signal-honesty-and-soa-global-gates.md) | codogotchi + **SoA upstream** | ✅ Shipped |
| **08** ⭐ | [phase-08-settings-window-and-observability.md](./phase-08-settings-window-and-observability.md) | codogotchi | ✅ Shipped — settings + bundled CLI |
| **09** | [phase-09-extended-platform-hooks.md](./phase-09-extended-platform-hooks.md) ([plan](../plans/phase-09-extended-platform-hooks.md)) | codogotchi | ✅ Shipped — five-platform hooks |
| **10** | [phase-10-floating-progression-hud.md](./phase-10-floating-progression-hud.md) ([plan](../plans/phase-10-free-rpg-tier.md)) | codogotchi | ✅ **Delivered** — Free RPG local tier |
| **11** | [phase-11-health-visuals-and-decay.md](./phase-11-health-visuals-and-decay.md) | codogotchi | Draft — sick-idle art (was decay visuals) |
| **12** | [phase-12-level-curve-100-and-migration.md](./phase-12-level-curve-100-and-migration.md) | codogotchi | **Superseded** — folded into Phase 10 |
| **13** | [phase-13-loot-equip-companion-and-custom-pets.md](./phase-13-loot-equip-companion-and-custom-pets.md) | codogotchi | Draft — loot / premium |
| **14** | [phase-14-premium-soa-animation-pack.md](./phase-14-premium-soa-animation-pack.md) | codogotchi | Draft — premium SoA pack |

**Son-of-Anton upstream (tracked in Phase 07 draft):** SoA writes directly to `~/.codogotchi/state.json` on gate emit — no intermediate `gate-events.ndjson` file. Plan separately in son-of-anton repo.

---

## Superseded / long-horizon

- [phase-2-social-health-drama.md](./phase-2-social-health-drama.md) — web armory, friends, leaderboard (not current ladder)
- [phase-1-cli-armory.md](./phase-1-cli-armory.md) — public launch vision
- [codogotchi-phase-04-05-roadmap.md](../../notes/public/codogotchi-phase-04-05-roadmap.md) — pre–Phase 04 ladder; SoA hook hardening folded into 06/07

---

## Suggested plan order

1. ✅ **05–09** install, parity, SoA gates, settings shell, extended hooks
2. ✅ **10** Free RPG tier (local HUD, v5 state, 1–100 curve)
3. **Next (product)** — **notarized DMG / distribution** (not in this index; see operator distribution notes)
4. **11** opt-in sync + leaderboard + enroll (when ready — security-sensitive)
5. **11 draft (art)** — sick-idle / health-tint sprites (renamed scope; decay math shipped in 10)
6. **13–14** loot, premium animation pack (paid Alive tier)
7. ~~**12**~~ — do not plan; curve lives in Phase 10

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
