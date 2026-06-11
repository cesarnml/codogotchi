# Contributing to Codogotchi

This is the developer reference. If you just want to *use* Codogotchi, see the [README](README.md) — download the app, drag it to Applications, done. This document is for building from source, working on the macOS app, or understanding the internals.

First time in the codebase? Read [START-HERE.md](START-HERE.md) for the mental model. All participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Architecture at a glance

Codogotchi is a platform-agnostic XP/animation layer for AI coding agents.

- A **hook binary** writes a closed-enum animation-state vocabulary to `~/.codogotchi/state.json` on every agent lifecycle event (Claude Code / Codex / Cursor / Copilot / Antigravity).
- The **macOS app** (`apps/menubar/`, Swift + SpriteKit) reads `state.json` and renders the pet — a static hero frame on the menu bar and an optional fully-animated floating desktop pet.
- An **XP / Health / Loot engine** (TypeScript, Bun) computes progression. It runs locally by default; cloud sync (Convex) is opt-in.
- The `.app` bundles its own `codogotchi` binary, so end users never touch a CLI or PATH.

The app owns all writes (hook install/update/remove, onboarding, pet selection). The CLI is a read/diagnostic surface plus internal subprocesses the app spawns.

## Repo layout

```
packages/
  cli/        # codogotchi + codogotchi-hook bins (Bun-only)
  cli-npm/    # minimal public `codogotchi` npm package (add/status/--version)
  engine/     # XP / Health / Loot pure logic + Bun-only sources/
  contracts/  # zod + types: IPC, signals, SoA event feed
  pets/       # pet-package validator + canonical repack
convex/       # Convex schema, mutations, HTTP action
apps/
  menubar/    # Codogotchi macOS app — menu bar + floating pet (Swift / SpriteKit)
plugins/
  hatch-codogotchi/  # AI spritesheet generation skills + scripts
web/          # codogotchi.app site (Astro)
docs/
  contracts/  # animation-state-vocabulary, soa-event-feed, convex-deployment
  product/    # plans, delivery, retrospectives
  runbooks/   # validation runbooks, scheduled-sync install
```

## Build from source

```bash
bun install
bun run mac:build
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Codogotchi.app' -path '*/Build/Products/*' | head -1)"
```

On first launch the app seeds Maew (`~/.codogotchi/pets/maew/`), presents the **Welcome to Codogotchi** consent sheet, and installs hooks on approval. See [`docs/runbooks/phase-08-lite-install.md`](docs/runbooks/phase-08-lite-install.md) for the full validation walk-through.

## Development

```bash
bun install
bun test                       # engine tests (fast)
bun run verify:quiet           # biome check (lint + format)
bun run spellcheck             # cspell
bun run ci:quiet               # publication gate (verify + spellcheck + mac:test)
bun run mac:build              # macOS app — xcodebuild
bun run mac:test               # macOS app — xcodebuild test
```

`mac:build` / `mac:test` shell out to `xcodebuild` against `apps/menubar/Codogotchi.xcodeproj`. `bun run ci` chains `mac:test` after biome + cspell so Swift failures gate the same place TS regressions do. `apps/**` is excluded from biome and from cspell's non-md scan; only `mac:test` crosses that boundary. See [`docs/product/plans/phase-02-as-shipped-ci-macos-tests.md`](docs/product/plans/phase-02-as-shipped-ci-macos-tests.md) for the divergence from the original TS-only CI plan.

Multi-ticket delivery is driven via the Son-of-Anton orchestrator under `.son-of-anton/`. See `AGENTS.md` for skill triggers and `.son-of-anton/docs/template/delivery/delivery-orchestrator.md` for the command surface.

## The macOS app

`apps/menubar/` is an `LSUIElement` menu bar agent with an optional float-on-top desktop pet and a Settings window (General / Pet / Developer / RPG / About tabs).

- **Settings → General** — the only user-facing surface for Install / Update / Remove hooks.
- **Settings → Pet** — enumerates and switches pets under `~/.codogotchi/pets/`.
- **Settings → RPG** — heart-HUD toggle and local progression controls.
- **Settings → Developer** — live `state.json`, `gate.json`, last-5 transitions, schema version, Cursor-bridge explainer (read-only).
- Menu items: **Settings…**, **Show/Hide Floating Pet**, **Open log folder**, **Reveal pet folder**, **Quit**.

The active pet is resolved from `~/.codogotchi/config.json` (`{ "pet": "maew" }`). A missing/malformed/absent `pet` key falls back to `"maew"` silently. `CODOGOTCHI_HOME` overrides the config root and is the test-isolation mechanism used in `PetConfigTests`.

**Demo mode** (`CODOGOTCHI_DEMO=1` or `--demo`) cycles activity states from a fixture without touching live `state.json`. Developer QA tool only — not a user-facing feature.

## CLI surface (diagnostic / internal)

The public CLI is trimmed to read/diagnostic commands. Hook management and onboarding live in **Settings → General** (app-owned). `setup`, `hooks install`, and `hooks uninstall` are still callable internally (the app spawns them) but are hidden from `--help`.

```
codogotchi rpg                                Cloud/social enrollment (handle + Convex); local RPG is on by default
codogotchi hooks status [--json]              Per-platform hook install + firing status
codogotchi status                             Cached profile, HP, recent loot — requires rpg_enabled
codogotchi sync                               One sync cycle — requires rpg_enabled
codogotchi loot [--limit N] [--tier T]        Loot history — requires rpg_enabled
codogotchi config get|set|list                Read/write/dump config (secrets redacted)
codogotchi vacation on|off|status             Pause/resume HP decay
```

| Env var | Default | Effect |
|---|---|---|
| `CODOGOTCHI_HOME` | `~/.codogotchi` | Config / cache / log root |
| `CODOGOTCHI_USER_ROOT` | OS home | Home dir used for hook installation |

The public npm `codogotchi` package (`packages/cli-npm`) is a **separate, minimal node build** over the bare name — only `add`, `status`, `--version`. App-owned write commands are not exposed. Installs are no-overwrite by default (`--force` to override) and re-validated against the pet contract before landing.

## Platform hooks

Native hooks for all five platforms install via **Settings → General → Install hooks** (or `codogotchi hooks install --platform <name>` internally). Restart the editor afterward.

| Platform | `source_origin` | Hook file |
|---|---|---|
| Claude Code | `claude_code` | `~/.claude/settings.json` |
| Codex | `codex` | Codex hooks |
| Cursor | `cursor` | `~/.cursor/hooks.json` |
| GitHub Copilot (VS Code) | `vscode` | `~/.copilot/hooks/codogotchi.json` |
| Google Antigravity | `antigravity` | `~/.gemini/config/hooks.json` |

`codogotchi hooks status` reports each platform's install + firing state. The canonical Copilot origin is `vscode` (`copilot` is accepted as a `CODOGOTCHI_ORIGIN` alias in manual overrides, but the installer always writes `vscode`).

**Bridge fallback:** if native hooks for Cursor/VS Code aren't installed but Claude Code hooks are, tool calls may route through the Claude Code bridge and report `source_origin: "claude_code"` (mislabeled). Prefer native install. `hooks status` reports `bridge` in that case.

See the [platform parity matrix](docs/runbooks/phase-09-platform-parity.md) for full event sets, config paths, tool-name mappings, and support levels.

## Where data lives

| Path | Owner | Purpose |
| --- | --- | --- |
| `~/.codogotchi/config.json` | app / `config` | Credentials, health knobs, active pet |
| `~/.codogotchi/profile.json` | `sync` | Local cache of Convex profile |
| `~/.codogotchi/state.json` | `codogotchi-hook` | Animation state for renderers (closed 19-state enum) |
| `~/.codogotchi/gate.json` | Son-of-Anton | Active delivery-gate state (`expires_at`-bounded) |
| `~/.codogotchi/app-state.json` | app | Floating pet visibility, position, size |
| `~/.codogotchi/state-transitions.log` | app | NDJSON log of state changes + heartbeats |
| `~/.codogotchi/sync.log` | `sync` | Per-source success / failure (rotated) |
| `~/.codogotchi/pets/<name>/` | app / user | Pet assets (`pet.json`, `spritesheet.webp`, lite-basic / lite-enhanced / soa sheets) |
| Convex `profiles`, `loot_events`, `users` | server | Canonical cloud state |

## Health semantics

Knobs in `~/.codogotchi/config.json`:

- `health.weekend_decay` — when `false` (default), HP doesn't drop Sat/Sun (local tz).
- `health.grace_days` — days of inactivity before HP starts decaying.
- `health.vacation_until` — ISO date through which HP decay is suspended (`codogotchi vacation on`).

## Pet gallery & publishing

[`codogotchi.app/gallery`](https://codogotchi.app/gallery) is the community marketplace. Pets install into `${CODOGOTCHI_HOME:-~/.codogotchi}/pets/<pet-id>/`, ready to pick in **Settings → Pet**. Publishing requires sign-in at [`/upload`](https://codogotchi.app/upload); every upload is server-validated, stripped to an allowlist, and re-packed into a canonical zip — the trust boundary is at upload. Minimum bar: a **Codex + Lite-Basic** pet (use [`hatch-codogotchi`](plugins/hatch-codogotchi/README.md) to generate one). Operators can unlist instantly; takedowns go to admin@codogotchi.app.

## Contracts to read before extending

- [`docs/contracts/animation-state-vocabulary.md`](docs/contracts/animation-state-vocabulary.md) — closed-enum state vocabulary the hook writes and the app reads (Swift `StateJsonReader`).
- [`docs/contracts/soa-event-feed.md`](docs/contracts/soa-event-feed.md) — NDJSON event feed Son-of-Anton emits for delivery-gate signals.
- [`docs/contracts/convex-deployment.md`](docs/contracts/convex-deployment.md) — deployment topology.
- [Spritesheet reference](https://codogotchi.app/docs/spritesheet) — the four-tier pet contract (Codex / Lite-Basic / Lite-Enhanced / SoA).
