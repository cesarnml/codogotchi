# Phase 08 Draft — Settings Window and Observability

_Drafted: 2026-05-27_
_Updated: 2026-05-29 — app-owned writes, read-only CLI product surface_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: ideation storm §3, developer settings/tab discussion (2026-05-27); app/CLI boundary discussion (2026-05-29)_

---

## Thesis

Replace JSON-and-Finder onboarding with a **Settings window**: the **only user-facing control plane** for mutating Codogotchi on disk — hooks, config, enrollment, pet selection, health knobs, and upgrades. **Lite** users live here to opt into RPG; **alive** users configure signals and inspect state.

The **Codogotchi app** owns all **writes** (via an in-process or XPC **install API** backed by the bundled `codogotchi` binary). The **`codogotchi` CLI** exposed to users is **read-only diagnostics** (`status`, `hooks status`, log/state dumps) — not a second install channel. That boundary keeps hook schema, hook binary, and menubar renderer on **one lockstep upgrade path**, so end users do not hit “v3 `state.json`, v2 app” gray failure from updating hook and app independently.

---

## App / CLI architecture (durable boundary)

Phase 05–06 still treat the CLI as a shared write surface (`setup`, `hooks install`, config mutation). Phase 08 **closes that split** for the product:

| Layer | Writes | Reads / diagnostics |
| --- | --- | --- |
| **Codogotchi.app (Settings, onboarding)** | Install / upgrade / uninstall hooks; seed or update `~/.codogotchi/config.json`; enroll (RPG); pet import/select; future health/config knobs | Surfaces hook health, last event, schema version mismatch hints in UI |
| **Bundled `codogotchi` binary** | Invoked **only by the app** (or dev builds) through an internal install API — not advertised as user-facing write commands | Same artifact; optional hidden/dev flags for local iteration |
| **`codogotchi` CLI (user-facing)** | **None** — no `hooks install`, `hooks uninstall`, `setup`, or `rpg` on the public command surface after this phase | `status`, `hooks status` (human + `--json`), state/log introspection, support-friendly dumps |
| **`codogotchi-hook` on disk** | Still invoked by Claude / Codex / Cursor on every agent event; version and path are **chosen by the app** when it writes platform hook JSON | N/A |

**Lockstep rule:** when the app upgrades (or user clicks **Update hooks** / first-run install), it upgrades **both** the embedded hook binary **and** the menubar renderer build that ships in the same `.app`. `EXPECTED_STATE_SCHEMA_VERSION` and `STATE_JSON_SCHEMA_VERSION` bump together in that release — not via `brew upgrade` hook while an old `.app` sits in `/Applications`.

**Gray Maew (schema newer than app)** remains the intentional forward-compat signal from Phase 02, but becomes a **developer / stale-build** case (old `.app`, new repo hook), not a normal consumer path.

**Dev escape hatch:** Xcode and local repo workflows may still call write paths directly for iteration; that is not the product contract and need not appear in README command tables.

---

## The problem

- RPG requires `codogotchi rpg` in Terminal (handle, Convex, GitHub, WakaTime) after Lite setup — **removed as product requirement**; enrollment moves in-app.
- Pet selection is `config.json` + Reveal `~/.codex/pets/` — **Settings Pet tab** owns selection and copy-into-home.
- Loot is CLI `loot` reading JSONL — no visual delight — **Loot tab** (read path; equip still deferred).
- No in-app view of `state.json` or transition log — **Developer tab**.
- Cursor users see the pet work with **empty `~/.cursor/hooks.json`** and cannot tell whether hooks are native, Claude-bridge, or broken — logs show `claude_code` during Cursor Agent work ([platform research](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md)).
- **Two-channel installs** (Terminal `hooks install` vs drag-and-drop `.app`) let hook and renderer drift — schema mismatch shows desaturated idle + “Update the menu bar app” ([forward-compat policy](../../contracts/animation-state-vocabulary.md)). Consumers should never depend on PATH or a separate CLI package to mutate install state.

---

## Committed scope

### Settings window shell

Menubar → **Settings…** opens a standard macOS window (not a tiny panel). Tabs:

| Tab | Lite | Alive (RPG) |
| --- | --- | --- |
| **General** | Hooks status summary; **Install / Update / Remove hooks** (sole user-facing hook controls) | Same + Convex handle, enroll CTA |
| **Pet** | List + select; Codex built-in + custom; import-on-select | Same + bundled pets |
| **Health** | Hidden or “Enable alive pet” CTA | `weekend_decay`, `grace_days`, death count (read-only), vacation status |
| **Loot** | Hidden or teaser | Read-only **gallery** from `loot.log` (WoW-style cards); equip disabled → “Codogotchi Pro” until Phase 13 |
| **Developer** | ✓ | Read-only: `state.json`, `state-transitions.log`, schema/renderer version; Reveal in Finder |
| **About** | ✓ | App + bundled hook version, links, product blurb |

### Hooks (General tab — write surface)

- **Install hooks**, **Update hooks** (refresh hook binary + platform JSON to match this app build), and **Remove hooks** live **only** here (and onboarding equivalents) — not in Terminal README flows.
- UI calls the app **install API** (Swift → bundled binary subprocess with stable flags), never “run `codogotchi hooks install` yourself.”
- Status display reuses the same JSON shape as `codogotchi hooks status --json` but is populated by the app (read path); optional **Copy diagnostics** for support.
- On schema mismatch (hook wrote newer `schema_version` than this build understands — should not happen after lockstep release), surface an in-app **Update Codogotchi** message instead of relying on menubar tooltip alone.

### Enable alive pet (RPG unlock)

- Primary CTA: **Turn on alive pet** → **in-app enroll wizard** (no public `codogotchi rpg` write command)
- Sets `features.rpg_enabled: true` via app install API; prompts for required Convex + handle; secrets in Keychain
- Unlocks Health + Loot tabs and Phase 10 HUD (if shipped)

### Pet tab (Codex-like)

- Enumerate **Codex built-in** pets (Dewey, Fireball, …) when `~/.codex/pets` present
- **Custom pets** section with path `~/.codogotchi/pets` + Open folder
- On select: **copy** `pet.json` + `spritesheet.webp` (+ codogotchi sheet if present) into `~/.codogotchi/pets/<id>/`
- Non-Codex users: show **bundled** pets only (Phase 05 seed)

### BYOP (document only in this phase; full validation Phase 13)

- Folder layout: `pet.json`, `codogotchi-animations.webp` (Codex rows), `codogotchi-soa-animations.webp` (SoA rows)
- Power users drop folder under `~/.codogotchi/pets/<id>/`

### Bundle the CLI binary + install API

Embed the `codogotchi` binary inside the app bundle (`Contents/MacOS/codogotchi` or `Contents/Resources/codogotchi`) so the app is a fully self-contained drag-and-drop artifact with no PATH prerequisites.

- **Install API (app → binary):** Swift façade with stable operations — `installHooks(platforms:)`, `uninstallHooks(platforms:)`, `upgradeHooksIfNeeded()`, `writeLiteConfig(...)`, `enrollRpg(...)` — implemented by invoking bundled binary subcommands that are **not** listed in public `--help` (or are documented as “app internal only”). Settings and onboarding call only this façade.
- `HookStatusClient` and install runners resolve the binary from the bundle first (`Bundle.main.bundleURL` + relative path), falling back to PATH **only in dev builds** where the bundle copy is absent.
- Same TypeScript codebase as today’s CLI; Xcode copy step produces the bundle artifact. Release train ships **one** consumer artifact: `Codogotchi.app` (renderer + install API + hook binary version pinned in About).
- Optional **standalone CLI package** (Homebrew, `npm`) may still ship for **diagnostics only** — same binary, public surface trimmed to read commands; must not document `hooks install` / `setup` / `rpg` as supported user workflows after Phase 08.

### CLI product surface (read-only)

Public commands retained for Terminal users, CI, and support:

- `codogotchi status` — home dir, config summary, current `state.json` activity (read)
- `codogotchi hooks status` / `hooks status --json` — per-platform install + firing inference (read)
- Future: `codogotchi logs tail`, `codogotchi state dump` — same observability as Developer tab, scriptable

**Removed or hidden from public CLI** (app Settings / onboarding only):

- `codogotchi setup`, `codogotchi rpg`, `codogotchi hooks install`, `codogotchi hooks uninstall`

README and runbook after Phase 08: “Install Codogotchi.app; use Settings to enable hooks” — not “run `codogotchi hooks install`.”

### Developer tab

- Pretty-print `state.json` (refresh button) — **read only**
- Pretty-print the **`gate.json` sidecar** (SoA-owned) — current gate, `since`, `expires_at`, and whether the gate animation is live or expired-into-badge (Phase 07 introduces the sidecar; SoA/son-of-anton Phase 17 writes it)
- Tail or paginate `state-transitions.log`
- Show **renderer schema version** vs **`state.json` `schema_version`** when they differ (explains gray pet without opening Finder); after Phase 07 the baseline is **schema v4**
- Toggle log verbosity for future hook fields (`tool_command`, gate fields) if exposed as a config write, route through install API (not raw JSON edit)
- **Hook diagnostics (lite + alive):** last-seen `source_event.origin` / tool name; bridge vs native Cursor guidance ([platform research](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md))
- Read-only summary: hooks present on disk per platform (derived from same logic as `hooks status --json`)

---

## Defers

- Loot **equip** actions → **Phase 13**
- Premium billing / StoreKit
- Premium custom pet generation service
- Notifications / Hooks advanced tabs
- Deprecation/removal of write subcommands from standalone `codogotchi` package (can ship app-first, then trim CLI `--help` in a follow-up PR)
- XPC vs in-process install API (implementation detail; contract is “app owns writes”)

---

## Exit conditions

1. Lite user can select pet and **install / update / remove hooks** from Settings only — no editing JSON, no Terminal install steps in README.
2. Alive user can enroll (handle, Convex, WakaTime, GitHub) entirely in-app — no `codogotchi rpg` in documented operator flow.
3. Developer tab shows live `state.json` matching hook output (read-only).
4. Loot tab renders at least one earned item as a card from `loot.log`.
5. Developer tab or help text answers “why does my pet react in Cursor when `~/.cursor/hooks.json` is empty?” without requiring external docs.
6. Fresh machine with only `Codogotchi.app` in `/Applications` — **no `codogotchi` on PATH** — completes onboarding + hook install via app; pet is full color with matching schema (no `schemaNewer` desaturated failure).
7. Public CLI `--help` lists only read/diagnostic commands; `hooks install` / `setup` / `rpg` absent or explicitly marked internal/deprecated.
8. Reinstalling the app and running **Update hooks** refreshes platform hook JSON to the bundled `codogotchi-hook` path and schema generation version shipped with that build.

---

## Dependencies

- **Phase 05** lite config + bundled pet (bootstrap semantics move under install API)
- **Phase 05** `rpg_enabled` flag (toggle becomes app-owned write)
- **Phase 07** schema v4 (19-state closed enum) + `gate.json` sidecar (lockstep rule assumes renderer and hook bump together in app releases; the sidecar adds a second state file the renderer must read)
- Recommended after **Phase 10** so Health tab matches HUD/decay (can parallelize)

---

## Open questions

1. Import-on-select: overwrite existing `~/.codogotchi/pets/<id>` or versioned copy?
2. CLI bundling: universal binary or arm64-only to match the app target?
3. Install API transport: subprocess to bundled CLI vs Swift-native hook JSON writer long-term (subprocess acceptable for Phase 08 if write flags stay app-private).
4. Standalone Homebrew formula: ship diagnostics-only CLI, or “app only” with `codogotchi` available only inside the bundle?
5. Auto **Update hooks** on app launch when embedded hook version ≠ last-installed version recorded in `app-state.json`?

---

## Next step

`/soa plan docs/product/drafts/phase-08-settings-window-and-observability.md`
