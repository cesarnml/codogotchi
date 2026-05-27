# Phase 10 Draft — Settings Window and Observability

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: ideation storm §3, developer settings/tab discussion (2026-05-27)_

---

## Thesis

Replace JSON-and-Finder onboarding with a **Settings window**: the control plane for **enabling alive pet**, credentials, pet selection, health knobs, loot preview, and debugging. **Lite** users live here to opt into RPG; **alive** users configure signals and inspect state.

---

## The problem

- RPG requires `codogotchi setup` in Terminal (handle, Convex, GitHub, WakaTime).
- Pet selection is `config.json` + Reveal `~/.codex/pets/`.
- Loot is CLI `loot` reading JSONL — no visual delight.
- No in-app view of `state.json` or transition log.
- Cursor users see the pet work with **empty `~/.cursor/hooks.json`** and cannot tell whether hooks are native, Claude-bridge, or broken — logs show `claude_code` during Cursor Agent work ([platform research](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md)).

---

## Committed scope

### Settings window shell

Menubar → **Settings…** opens a standard macOS window (not a tiny panel). Tabs:

| Tab | Lite | Alive (RPG) |
| --- | --- | --- |
| **General** | Convex handle (greyed until enroll), link to enroll | WakaTime API key, GitHub username, GitHub PAT, Convex handle — Keychain for secrets |
| **Pet** | List + select; Codex built-in + custom; import-on-select | Same + bundled pets |
| **Health** | Hidden or “Enable alive pet” CTA | `weekend_decay`, `grace_days`, death count (read-only), vacation status |
| **Loot** | Hidden or teaser | Read-only **gallery** from `loot.log` (WoW-style cards); equip disabled → “Codogotchi Pro” until Phase 12 |
| **Developer** | ✓ | Concise vs verbose; view `state.json`, `state-transitions.log`; Reveal in Finder |
| **About** | ✓ | Version, links, product blurb |

### Enable alive pet (RPG unlock)

- Primary CTA: **Turn on alive pet** → runs enroll flow (in-app wizard or spawns `codogotchi enroll`)
- Sets `features.rpg_enabled: true`; prompts for required Convex + handle
- Unlocks Health + Loot tabs and Phase 08 HUD (if shipped)

### Pet tab (Codex-like)

- Enumerate **Codex built-in** pets (Dewey, Fireball, …) when `~/.codex/pets` present
- **Custom pets** section with path `~/.codogotchi/pets` + Open folder
- On select: **copy** `pet.json` + `spritesheet.webp` (+ codogotchi sheet if present) into `~/.codogotchi/pets/<id>/`
- Non-Codex users: show **bundled** pets only (Phase 05 seed)

### BYOP (document only in this phase; full validation Phase 12)

- Folder layout: `pet.json`, `codogotchi-animations.webp` (Codex rows), `codogotchi-soa-animations.webp` (SoA rows)
- Power users drop folder under `~/.codogotchi/pets/<id>/`

### Developer tab

- Pretty-print `state.json` (refresh button)
- Tail or paginate `state-transitions.log`
- Toggle log verbosity for future hook fields (`work_mode`, `tool_command`)
- **Hook diagnostics (lite + alive):** show last-seen `source_event.origin` / tool name; explain when `claude_code` + `Shell`/`Grep` likely means **Cursor via third-party bridge** (link: enable **Third-party skills**, verify `~/.claude/settings.json` contains `codogotchi-hook`, contrast with empty `~/.cursor/hooks.json`)
- Optional read-only summary: hooks installed in Claude / Codex / Cursor native paths (file exists + Codogotchi command present)

---

## Defers

- Loot **equip** actions → **Phase 12**
- Premium billing / StoreKit
- Premium custom pet generation service
- Notifications / Hooks advanced tabs

---

## Exit conditions

1. Lite user can select pet and install hooks from Settings without editing JSON.
2. Alive user can set WakaTime + GitHub + handle without Terminal.
3. Developer tab shows live `state.json` matching hook output.
4. Loot tab renders at least one earned item as a card from `loot.log`.
5. Developer tab or help text answers “why does my pet react in Cursor when `~/.cursor/hooks.json` is empty?” without requiring external docs.

---

## Dependencies

- **Phase 05** lite config + bundled pet
- **Phase 05** `rpg_enabled` flag
- Recommended after **Phase 08–09** so Health tab matches HUD/decay (can parallelize)

---

## Open questions

1. In-app enroll vs always Terminal for Convex registration?
2. Import-on-select: overwrite existing `~/.codogotchi/pets/<id>` or versioned copy?

---

## Next step

`/soa plan docs/product/drafts/phase-10-settings-window-and-observability.md`
