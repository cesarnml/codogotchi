# Phase 05 Draft — Lite Install and Onboarding

_Drafted: 2026-05-27_
_Status: Draft input — product plan at `docs/product/plans/phase-05-lite-install-and-onboarding.md` (grill-me complete, awaiting approval)_
_Source: [codogotchi-ideation-storm-roadmap-draft.md](../../notes/public/codogotchi-ideation-storm-roadmap-draft.md), lite-vs-alive product model_

---

## Thesis

Codogotchi should install like a **native Codex-class desktop pet**: hooks + app, no Convex handle, no WakaTime, no “RPG enrollment” on day one. The menubar and floating pet are already a `state.json` visualizer; **Phase 01–02 coupling** (everything flows through `codogotchi setup`) is the main onboarding wall.

This phase splits install paths and introduces **`features.rpg_enabled: false`** as the default for new users. **Alive pet** (XP, health decay, loot, sync) unlocks later from Settings (Phase 10).

---

## The problem

Today `codogotchi setup` always:

1. Prompts for handle, GitHub pair, WakaTime, **Convex HTTP URL**
2. POSTs `/sync` to register the profile
3. Installs Claude + Codex hooks (with `CODOGOTCHI_CONVEX_URL` in the hook command even though the hook binary does not use it at runtime)

Users who only want “pet that reacts to my agent” must still enroll in the full RPG pipeline. The macOS app already launches without Convex; README and CLI messaging do not reflect that.

---

## Product modes (locked for this phase family)

| Mode | Default? | User gets |
| --- | --- | --- |
| **Lite** | Yes (new installs) | `hooks install` + Codogotchi.app; hook-driven animation; SoA gates when present; `hp` defaults to 100 / thriving unless `profile.json` exists |
| **Alive (RPG)** | Opt-in via Settings (Phase 10) or `codogotchi enroll` | Convex handle, sync, signals, health/XP/loot — existing Phase 01 engine |

---

## Committed scope

### 1. CLI: split install from enroll

- **`codogotchi hooks install`** — installs Claude Code + Codex hook entries; writes minimal `~/.codogotchi/config.json` if absent:
  - `features.rpg_enabled: false`
  - optional `pet` name (default bundled pet id)
  - **no** required `handle` or `convex_http_url`
- **`codogotchi enroll`** (or `setup --rpg`) — current interactive flow: handle, Convex URL, optional GitHub/WakaTime, first `/sync`, sets `features.rpg_enabled: true`
- **`codogotchi setup`** — deprecate as alias with migration notice, or keep as alias to `enroll` only (product decision in plan)
- Remove `CODOGOTCHI_CONVEX_URL` from hook shell command unless a future hook feature needs it

### 2. Config schema evolution

- Add `features: { rpg_enabled: boolean }` (default `false` for `hooks install`, `true` after `enroll`)
- Make `handle` and `convex_http_url` **optional** when `rpg_enabled === false`
- `sync`, `status`, `loot` (RPG commands) refuse with clear message when RPG disabled: point to Settings or `codogotchi enroll`
- Backward compat: existing configs without `features` → treat as `rpg_enabled: true` (do not break current devs)

### 3. Bundled default pet (non-Codex path)

- Ship at least one complete pet in app resources (`pet.json` + Codex sheet + codogotchi sheet)
- On first app launch (or first `hooks install`), seed `~/.codogotchi/pets/<id>/` if no pet is loadable
- Menubar must not depend on `~/.codex/pets/mali/` for first-run success

### 4. Codex import-on-select (minimal)

- If `~/.codex/pets/*` exists, allow choosing a pet id in config without full Settings UI (CLI `config set pet <id>` or tiny prompt in `hooks install`)
- **Copy** (not live-read) selected Codex pet assets into `~/.codogotchi/pets/<id>/` on first selection — canonical store for runtime (full Pet tab UI in Phase 10)

### 5. Menubar / README messaging

- Menu: **Install hooks…** (opens help or runs documented command) vs **Enable alive pet…** (deferred UI wire to Phase 10; stub or deep-link OK)
- README: “Lite install” path (3 steps: build app, `hooks install`, use agent) separate from “Alive pet” path
- No HUD / hearts / XP UI in this phase (Phase 08+, gated)

### 6. Hook behavior in lite mode

- Continue writing `state.json` on every hook invocation
- If `profile.json` absent, `hp: 100`, `hp_overlay: thriving` (current behavior)
- Do not require sync cron for animation

### 7. Document Cursor via Claude third-party hooks (no native installer in this phase)

**Field finding (2026-05-27):** Many Cursor users already see the pet react during **Cursor Agent** work with an **empty** `~/.cursor/hooks.json`. Cursor can load hooks from **`~/.claude/settings.json`** when **Third-party skills** is enabled ([Cursor docs](https://cursor.com/docs/reference/third-party-hooks)). `hooks install` wires `codogotchi-hook` there (same as today’s `setup`); the menubar app only polls `~/.codogotchi/state.json` — it never reads Cursor’s hooks file directly.

**Lite onboarding must say this plainly:**

| What users see | What is actually happening |
| --- | --- |
| Pet moves in Cursor | Cursor fired `codogotchi-hook` via the **Claude-compat bridge**, not `~/.cursor/hooks.json` |
| Log says `source_origin: claude_code` | **Heuristic mis-label** — Cursor sends camelCase events (`preToolUse`); hook defaults non-snake_case to `claude_code` |
| Tool names `Shell`, `Grep`, `Write` | Fingerprint of **Cursor Agent** stdin (Claude Code hooks typically see `Bash`) |

README / runbook: verify bridge with `jq '.hooks' ~/.claude/settings.json | grep codogotchi-hook` and `tail -f ~/.codogotchi/state-transitions.log`. Call out **Third-party skills** in Cursor Settings. Native `~/.cursor/hooks.json` install and truthful `source_origin: cursor` → **Phase 06**.

---

## Defers

- Native multi-platform hooks (`~/.cursor/hooks.json`, VS Code, Antigravity) and truthful `source_origin` → **Phase 06** (Cursor may already animate via Claude bridge until then)
- Attention tray, TTL, bubble UX → **Phase 06**
- Settings window and RPG unlock UI → **Phase 10**
- Convex schema changes
- Premium / loot / equip

---

## Exit conditions

1. New user can run **`codogotchi hooks install`** + open app and see animated pet from bundled assets **without** Convex credentials.
2. Existing Phase 01 users with full `config.json` behave unchanged (`rpg_enabled` implied true).
3. `codogotchi sync` fails fast with actionable message when RPG disabled.
4. `enroll` path still registers profile and installs hooks idempotently.

---

## Dependencies

- None on Phase 06+; **blocks** meaningful adoption story for platform parity phase.

---

## Cross-repo

- Son-of-Anton: no code required; `.soa/events.ndjson` continues to work when consumer runs SoA with `codogotchi.enabled` (lite users benefit automatically on hook fire — including Cursor sessions that invoke `codogotchi-hook` through the Claude bridge).

---

## Open questions (for `/soa plan`)

1. Command naming: `enroll` vs `setup --rpg` vs keep `setup` for RPG only?
2. Single bundled pet id (Mali vs Maew vs new mascot)?
3. App-first vs CLI-first seeding of `~/.codogotchi/pets/`?
4. Lite README: lead with “works in Cursor today via Third-party skills + Claude hooks” vs wait until Phase 06 native Cursor installer?

---

## Next step

`/soa plan docs/product/drafts/phase-05-lite-install-and-onboarding.md`
