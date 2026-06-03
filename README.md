# codogotchi

Codogotchi is the RPG layer on top of Codex- and Claude-format pets. Your
agent activity feeds XP, HP, stage advancement, and loot. The data lives in
Convex; a macOS **Codogotchi** app renders agent animation state locally from
`~/.codogotchi/state.json` on the menu bar (static hero frame per state) and an
optional transparent floating desktop pet (full animation while visible).

**Status:** Phase 09 shipped — native hook integration for GitHub Copilot (VS Code Agent) and Google
Antigravity, with five-platform support. Phase 08: Lite-and-SoA v1 release gate (private). The `.app`
is self-contained: it bundles the `codogotchi` binary so no PATH prerequisite exists. Settings
(General / Pet / Developer / About) is the control plane for hooks and pet selection. Hook
install/update/remove live only in Settings → General. The two real 8-frame Maew spritesheets
(`codogotchi-lite-spritesheet.webp` + `codogotchi-soa-spritesheet.webp`) ship, making Lite and
SoA visualization work end to end. Earlier phases: 01 CLI + Convex pipeline; 02 menu bar NSStatusItem;
03 all 19 activity states + codogotchi spritesheet; 04 floating pet + Codogotchi rename; 05 Lite vs
Alive modes + mandatory onboarding + canonical pet store; 06 attention bubble + sticky SoA gate +
Cursor platform adapter; 07 schema v4 + gate.json sidecar + renderer merge. See the
[`phase-08 install runbook`](docs/runbooks/phase-08-lite-install.md) and the
[`phase-09 platform parity matrix`](docs/runbooks/phase-09-platform-parity.md).

## What ships in Phase 01

- A Bun-powered CLI (`codogotchi`) with `setup`, `sync`, `status`, `loot`,
  `config`, `vacation`.
- A hook binary (`codogotchi-hook`) that writes a documented animation-state
  vocabulary to `~/.codogotchi/state.json` on every Claude Code / Codex
  lifecycle event.
- XP / Health / Loot engine wired through the CLI and re-used inside Convex's
  `syncProfile` mutation, so XP is computed server-side and the CLI is a dumb
  pipe + cache reader.
- Four signal sources: Claude Code JSONL, Codex JSONL, GitHub merged PRs (with
  `scorePR` quality enrichment), Wakatime hours. **Forward-only:** each source
  reads activity since the last sync (or since install time on first sync)—no
  historical backfill. Per-source XP **accumulates** on each successful sync.
- Convex Cloud schema covering `profiles` (with HP fields), `loot_events`,
  `users`; a `syncProfile` mutation; an HTTP action receiving signals from
  the CLI.
- Scheduled-sync installers for launchd and cron, a `scorePR` debug log, and a
  validation runbook.

Public surface (web armory, leaderboard, OAuth, OG image, install script,
macOS pet, visible loot rendering) is intentionally deferred. See
[`docs/product/plans/phase-01-cli-convex-plumbing.md#explicit-deferrals`](docs/product/plans/phase-01-cli-convex-plumbing.md#explicit-deferrals).

## Repo layout

```
packages/
  cli/        # codogotchi + codogotchi-hook bins (Bun-only)
  engine/     # XP / Health / Loot pure logic + Bun-only sources/
  contracts/  # zod + types: IPC, signals, SoA event feed
convex/       # Convex schema, mutations, HTTP action
apps/
  menubar/    # Codogotchi macOS app — menu bar + floating pet (Swift / SpriteKit)
docs/
  contracts/  # animation-state-vocabulary, soa-event-feed, convex-deployment
  product/    # plans, delivery, retrospectives
  runbooks/   # phase validation runbooks, scheduled-sync install
```

## Install (private, source build)

There is no App Store or notarized DMG yet. See the
[`phase-08 Lite install runbook`](docs/runbooks/phase-08-lite-install.md) for the full walk-through.

**No PATH prerequisite.** The `.app` bundles its own `codogotchi` binary (Phase 08). Install the app
and use Settings → General to enable hooks — no Terminal commands required.

Quick path via debug build:

```bash
bun install
bun run mac:build
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Codogotchi.app' -path '*/Build/Products/*' | head -1)"
```

On first launch the app presents a **Welcome to Codogotchi** consent sheet. Approve to install
hooks. After closing the sheet, open **Settings → General** at any time to install, update, or
remove hooks, and **Settings → Pet** to switch pets.

## Tiers (animation vs local RPG vs cloud)

| Tier | Config | Network | Progression |
|---|---|---|---|
| **Animation-only** | `features.rpg_enabled: false` (default on first launch today) | No | Hook-driven pet animation only |
| **Free RPG (local)** | `features.rpg_enabled: true` (no Convex fields required) | No | Hearts, level 1–100, XP ring via local JSONL + hooks; HUD opt-out: `features.rpg_hud_enabled: false` in **Settings → RPG** |
| **Alive + sync** | `rpg_enabled: true` + cloud profile fields | Yes (when configured) | `sync`, leaderboard — Phase 11+ |

Enable local RPG with `codogotchi rpg` (interactive setup) or set `features.rpg_enabled: true` in `~/.codogotchi/config.json`. Cloud-backed commands (`sync`, `status`, `loot`, `vacation`) still require a enrolled cloud profile when implemented; local progression does not need a Convex URL.

## CLI surface

Phase 08 trimmed the public CLI to read/diagnostic commands. Hook management and onboarding live in
**Settings → General** (app-owned). `setup`, `hooks install`, and `hooks uninstall` are still callable
internally (the app spawns them as subprocesses) but are hidden from `--help`.

```
codogotchi rpg                                Enable local RPG (`rpg_enabled: true`); may prompt for cloud enroll when configured
codogotchi hooks status [--json]              Print per-platform hook install + firing status
codogotchi status                             Cached profile, HP, recent loot — requires rpg_enabled: true

codogotchi sync                               One sync cycle — requires rpg_enabled: true
codogotchi loot [--limit N] [--tier T]        Loot history — requires rpg_enabled: true
codogotchi config get <key>                   Read a dotted config key
codogotchi config set <key> <value>           Write a typed value
codogotchi config list                        Full config as JSON (secrets redacted)
codogotchi vacation on [--until YYYY-MM-DD]   Pause HP decay — requires rpg_enabled: true
codogotchi vacation off                       Resume HP decay
codogotchi vacation status                    Show vacation state
```

Environment overrides:

| Var | Default | Effect |
|---|---|---|
| `CODOGOTCHI_HOME` | `~/.codogotchi` | Config / cache / log root |
| `CODOGOTCHI_USER_ROOT` | OS home | Home dir used for hook installation |

## Cursor install paths

Codogotchi has **first-class native Cursor hooks** (`~/.cursor/hooks.json`). Install via
**Settings → General → Install hooks** (writes Codex, Claude Code, and Cursor), then **restart Cursor**.

Events fire with `source_origin: "cursor"`. `codogotchi hooks status` reports `cursor: native` when
`~/.cursor/hooks.json` contains Codogotchi entries.

CLI-only install:

```bash
codogotchi hooks install --platform cursor
```

### Bridge fallback (optional)

If native Cursor hooks are not installed but Claude Code hooks are, Cursor's **Third-party skills**
feature can route tool calls through Claude Code hooks. Events then show `source_origin: "claude_code"`.
`codogotchi hooks status` reports `cursor: bridge` in that case.

### GitHub Copilot (VS Code) and Antigravity (Phase 09)

Native hooks for **GitHub Copilot / VS Code Agent** and **Google Antigravity** shipped in Phase 09.
Install via:

```bash
codogotchi hooks install --platform vscode       # writes ~/.copilot/hooks/codogotchi.json
codogotchi hooks install --platform antigravity  # writes ~/.gemini/config/hooks.json
```

Events fire with `source_origin: "vscode"` and `source_origin: "antigravity"` respectively. The
animation badge and attention bubble show the correct platform logo for all five supported origins.
`codogotchi hooks status` reports each platform's install and firing state.

**`vscode`/`copilot` alias:** The canonical `source_origin` is `vscode`; `copilot` is accepted as a
`CODOGOTCHI_ORIGIN` alias in manual overrides but the installer always writes `vscode`.

**Bridge caveat:** VS Code may animate via the `.claude/settings.json` bridge if only Claude Code hooks
are installed — events then show `source_origin: "claude_code"` (mislabeled). Prefer native install.

See the [`platform parity matrix`](docs/runbooks/phase-09-platform-parity.md) for full event sets,
config paths, tool-name mappings, and support levels across all five platforms.

## Where data lives

| Path | Owner | Purpose |
| --- | --- | --- |
| `~/.codogotchi/config.json` | `setup`, `config` | Credentials, health knobs, and pet name |
| `~/.codogotchi/profile.json` | `sync` | Local cache of Convex profile |
| `~/.codogotchi/state.json` | `codogotchi-hook` | Animation state for renderers (`schema_version: 4`, v4 19-state enum) |
| `~/.codogotchi/gate.json` | son-of-anton Phase 17 | Active delivery gate state (written by SoA, read by renderer; `expires_at`-bounded) |
| `~/.codogotchi/app-state.json` | Codogotchi app | Floating pet visibility, position, size (`schema_version: 1`) |
| `~/.codogotchi/state-transitions.log` | Codogotchi app | NDJSON log of state changes and heartbeats |
| `~/.codogotchi/sync.log` | `sync` | Per-source success / failure (rotated) |
| `~/.codogotchi/loot.log` | `sync` (via Convex) | Loot history (for `loot`) |
| `~/.codogotchi/scorePR.log` | `sync` | `scorePR` heuristic decisions |
| `~/.codogotchi/pets/<name>/` | app / user | Canonical pet assets — Maew seeded from bundle on first launch (`pet.json`, `spritesheet.webp`, `codogotchi-lite-spritesheet.webp`, `codogotchi-soa-spritesheet.webp`) |
| Convex `profiles`, `loot_events`, `users` | server | Canonical state |

## Health semantics

Three knobs in `~/.codogotchi/config.json`:

- `health.weekend_decay` — when `false` (default), HP does not drop Sat/Sun in
  the local timezone.
- `health.grace_days` — days of inactivity before HP starts decaying.
- `health.vacation_until` — ISO date through which HP decay is suspended; set
  via `codogotchi vacation on`.

## macOS app (Phase 08)

The **Codogotchi** app (`apps/menubar/`) is an `LSUIElement` menu bar agent with an optional
float-on-top desktop pet and a Settings window (General / Pet / Developer / About tabs). The `.app`
bundles its own `codogotchi` binary — no PATH prerequisite.

On first launch the app seeds Maew from the bundle (`~/.codogotchi/pets/maew/`), presents a
**Welcome to Codogotchi** consent sheet, and installs hooks on approval. After onboarding,
**Settings → General** is the only user-facing surface for Install / Update / Remove hooks.
**Settings → Pet** enumerates and switches pets. **Settings → Developer** shows live `state.json`,
`gate.json`, last-5 transitions, schema version, and the Cursor-bridge explainer (read-only).

Build:

```bash
bun run mac:build
# For validation, see docs/runbooks/phase-08-lite-install.md
```

Menu items include **Settings…**, **Show/Hide Floating Pet**, **Open log folder**, **Reveal pet
folder** (opens `~/.codogotchi/pets/` in Finder), and **Quit Codogotchi**.

**Demo mode** (`CODOGOTCHI_DEMO=1` or `--demo` launch argument) cycles activity
states from a fixture without touching live `~/.codogotchi/state.json`. This is
a **developer QA tool only** — it is not a user-facing Lite feature and should
not be presented as one.

## Pet configuration (Phase 05+)

The Codogotchi app resolves the active pet from `~/.codogotchi/config.json`:

```json
{ "pet": "maew" }
```

The `pet` key selects asset directories under `~/.codogotchi/pets/<name>/`
(canonical store). Maew is bundle-seeded on first launch; no manual copy needed.
The compiled-in default is `"maew"`. A missing, malformed, or `pet`-key-absent
config falls back to `"maew"` silently. The menu bar's **Reveal pet folder**
item opens `~/.codogotchi/pets/` in Finder so you can inspect or swap the
active pet.

The env var `CODOGOTCHI_HOME` overrides the config file path for the menubar
app and is the test-isolation mechanism used in `PetConfigTests`.

## Contracts to read before extending

- [`docs/contracts/animation-state-vocabulary.md`](docs/contracts/animation-state-vocabulary.md) —
  closed-enum state vocabulary the hook writes and the Codogotchi app reads
  (Swift `StateJsonReader` in `apps/menubar/`).
- [`docs/contracts/soa-event-feed.md`](docs/contracts/soa-event-feed.md) —
  NDJSON event feed Son-of-Anton emits that the hook consumes for explicit
  delivery-gate signals.
- [`docs/contracts/convex-deployment.md`](docs/contracts/convex-deployment.md) —
  deployment topology.

## Development

```bash
bun install
bun test                       # engine tests (fast)
bun run verify:quiet           # biome check (lint + format)
bun run spellcheck             # cspell
bun run ci:quiet               # publication gate (verify + spellcheck + mac:test)
bun run mac:build              # Codogotchi macOS app — xcodebuild
bun run mac:test               # Codogotchi macOS app — xcodebuild test
```

`mac:build` and `mac:test` shell out to `xcodebuild` against
`apps/menubar/Codogotchi.xcodeproj`. `bun run ci` and `bun run ci:quiet`
chain `mac:test` after biome + cspell so Swift compile / test
failures gate the orchestrator's `post-red` and `open-pr` steps in
the same place TS regressions are caught. `apps/**` is still
excluded from biome and from cspell's non-md scan per the toolchain
seam decision; only `mac:test` crosses the boundary. See
[`docs/product/plans/phase-02-as-shipped-ci-macos-tests.md`](docs/product/plans/phase-02-as-shipped-ci-macos-tests.md)
for the divergence from the original "ci stays TS-only" Phase 02
plan.

Multi-ticket phase delivery is driven via the Son-of-Anton orchestrator
checked in under `.son-of-anton/`. See `AGENTS.md` for skill triggers and
`.son-of-anton/docs/template/delivery/delivery-orchestrator.md` for the
command surface.

## License

Private repository. No license granted.
