# Start Here

New to the Codogotchi codebase? This page gives you the mental model in five minutes. For build instructions and the full developer reference, continue to [CONTRIBUTING.md](CONTRIBUTING.md).

## What Codogotchi is

A macOS desktop pet that reacts to your AI coding agent in real time. Your agent fires lifecycle events (thinking, coding, testing, erroring); Codogotchi turns them into animations, plus an optional local-first XP/Health/Loot game layer.

## The mental model

Each active AI platform writes its own slice file to `~/.codogotchi/state.d/`. The app spawns one floating pet window per active platform.

```
  Your AI agents
  (Claude Code · Codex · Cursor · Copilot · Antigravity)
        │
        │  lifecycle hook events
        ▼
  codogotchi-hook  ──────────────  compiled Bun binary, bundled inside the .app
        │                          one hook instance per platform session
        │  writes a per-platform slice + global RPG state
        ▼
  ~/.codogotchi/state.d/<origin>:<session_id>.json   ←── activity-signal slice (v8)
  ~/.codogotchi/rpg-state.json                       ←── global RPG values (level, HP, hearts)
  ~/.codogotchi/customization.json                   ←── per-platform display mode + TTL + session pets (opt-in) + cap
  ~/.codogotchi/assignments.json                     ←── per-platform pet assignment (schema_version: 1)
  ~/.codogotchi/session-labels.json                  ←── per-session rename labels (Swift-owned, app-side only)
        │
        │  watched by
        ▼
  Codogotchi.app (Swift + AppKit/SpriteKit) — v2.2.0
  ├─ menu bar icon (static app icon — no animation)
  ├─ one floating desktop pet window per active platform (fully animated); with Session Pets on,
  │  one panel per concurrent agent session on that platform instead of one shared panel
  └─ Settings — the ONLY surface that installs/updates/removes hooks
        │   ├─ General: hooks, monochrome icon toggle
        │   ├─ Pet: per-platform pet assignment (Default slot + 5 platform overrides)
        │   ├─ Platform Settings: per-platform mode (own/combined/minimalist/off) + idle-dismiss TTL +
        │   │     Session Pets (opt-in, Own/Minimalist only) + Session Cap (2–10 or Unlimited, default 3)
        │   └─ RPG: HUD toggle
        ├─ XP / Health / Loot engine (TypeScript, runs locally by default)
        └─ opt-in cloud sync ───►  Convex (profiles, loot, pet gallery)
                                       ▲
                                       │  upload / browse / install pets
                              codogotchi.app website (Astro, Vercel)
```

Two invariants make the whole system legible:

1. **The app owns all writes.** Hook install/update/remove, onboarding, and pet assignment happen in the app's Settings. The `codogotchi` CLI is a read/diagnostic surface (`status`, `hooks status`, `loot`, `config`, `vacation`) plus internal subprocesses the app spawns. End users never need a terminal. **Breaking change in v2.1.0:** `codogotchi config set pet <id>` is removed — use Settings → Pet to assign pets.
2. **`state.d/` is a closed contract.** The hook binary writes a fixed 19-state activity vocabulary into per-platform slice files; the Swift app reads the directory and routes each origin (with Session Pets on, each `origin:session_id`) to its floating window. The TypeScript and Swift sides each pin `schema_version: 8` and must move in lockstep (see [`docs/contracts/animation-state-vocabulary.md`](docs/contracts/animation-state-vocabulary.md) and [`docs/contracts/customization-json.md`](docs/contracts/customization-json.md)). Per-platform pet identity (`assignments.json`, schema_version: 1) and per-session rename labels (`session-labels.json`, Swift-owned) are both stored separately from state slices and have no lockstep dependency; the session number itself is an in-memory free-list, not persisted.

## The five pieces

| Piece | Where | What it is |
| --- | --- | --- |
| macOS app | `apps/menubar/` | Swift/SpriteKit menu bar agent + floating pet + Settings |
| CLI & hook | `packages/cli/` | `codogotchi` and `codogotchi-hook` Bun binaries, compiled standalone and embedded in the .app |
| Engine | `packages/engine/` | Pure XP/Health/Loot logic, local-first |
| Backend | `convex/` | Convex schema, mutations, upload validation, sync HTTP action — powers the opt-in cloud layer and the pet gallery |
| Website | `web/` | codogotchi.app (Astro) — download, gallery, hatch, docs |

Supporting casts: `packages/contracts/` (zod types shared across the boundary), `packages/pets/` (pet-package validator + canonical repack — the gallery's trust boundary), `plugins/hatch-codogotchi/` (AI spritesheet generation skills).

## Pets are data, not code

A pet is a folder of `pet.json` (camelCase keys: `id`, `displayName`, …) plus up to four spritesheet tiers (Codex / Lite-Basic / Lite-Enhanced / SoA). The same package format works for the bundled pet (Maew), hand-drawn pets, AI-hatched pets, and gallery uploads. Uploads are server-validated, stripped to an allowlist, and re-packed before anyone can install them. Spec: [codogotchi.app/docs/spritesheet](https://codogotchi.app/docs/spritesheet).

## Where to start reading

- **Want to touch the pet/animation pipeline?** `docs/contracts/animation-state-vocabulary.md`, then `apps/menubar/`.
- **Want to touch the CLI or hooks?** `packages/cli/bin/`, then the platform parity matrix in `docs/runbooks/`.
- **Want to touch the game layer?** `packages/engine/` (pure functions, fast tests).
- **Want to touch the gallery/upload path?** `packages/pets/src/validate-repack.ts`, then `convex/actions/`.
- **Want to touch the website?** `web/src/pages/`.

## Ground rules

- Be kind: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Build, test, and workflow reference: [CONTRIBUTING.md](CONTRIBUTING.md).
- License: [MIT](LICENSE).
