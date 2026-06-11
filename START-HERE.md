# Start Here

New to the Codogotchi codebase? This page gives you the mental model in five minutes. For build instructions and the full developer reference, continue to [CONTRIBUTING.md](CONTRIBUTING.md).

## What Codogotchi is

A macOS desktop pet that reacts to your AI coding agent in real time. Your agent fires lifecycle events (thinking, coding, testing, erroring); Codogotchi turns them into animations, plus an optional local-first XP/Health/Loot game layer.

## The mental model

Everything flows through one file: `~/.codogotchi/state.json`.

```
  Your AI agent
  (Claude Code · Codex · Cursor · Copilot · Antigravity)
        │
        │  lifecycle hook events
        ▼
  codogotchi-hook  ──────────────  compiled Bun binary, bundled inside the .app
        │
        │  writes a closed-enum animation state
        ▼
  ~/.codogotchi/state.json  ◄───── the single contract between writers and renderers
        │
        │  watched by
        ▼
  Codogotchi.app (Swift + SpriteKit)
  ├─ menu bar pet (static hero frame)
  ├─ floating desktop pet (fully animated)
  └─ Settings — the ONLY surface that installs/updates/removes hooks
        │
        ├─ XP / Health / Loot engine (TypeScript, runs locally by default)
        └─ opt-in cloud sync ───►  Convex (profiles, loot, pet gallery)
                                       ▲
                                       │  upload / browse / install pets
                              codogotchi.app website (Astro, Vercel)
```

Two invariants make the whole system legible:

1. **The app owns all writes.** Hook install/update/remove, onboarding, and pet selection happen in the app's Settings. The `codogotchi` CLI is a read/diagnostic surface (`status`, `hooks status`, `loot`, `config`, `vacation`) plus internal subprocesses the app spawns. End users never need a terminal.
2. **`state.json` is a closed contract.** The hook binary writes a fixed 19-state animation vocabulary; the Swift app reads it. The TypeScript and Swift sides each pin a schema version and must move in lockstep (see [`docs/contracts/animation-state-vocabulary.md`](docs/contracts/animation-state-vocabulary.md)).

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
- License: [PolyForm Noncommercial 1.0.0](LICENSE).
