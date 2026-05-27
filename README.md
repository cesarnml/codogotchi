# codogotchi

Codogotchi is the RPG layer on top of Codex- and Claude-format pets. Your
agent activity feeds XP, HP, stage advancement, and loot. The data lives in
Convex; a macOS **Codogotchi** app renders agent animation state locally from
`~/.codogotchi/state.json` on both the menu bar micro-pet and an optional
transparent floating desktop pet.

**Status:** Phase 04 — Floating pet (private). Phase 01 CLI + Convex pipeline
is shipped; Phase 02 added the menu bar `NSStatusItem`; Phase 03 extended to
all 15 activity states with a second spritesheet (`codogotchi-spritesheet.webp`)
and per-pet config; Phase 04 renamed the app to **Codogotchi**, added a
float-on-top SpriteKit surface (show/hide, drag, resize, persistence in
`~/.codogotchi/app-state.json`), shared live/demo state fanout, and mouse-
reactive reserved Codex rows. HP overlays, focus-aware visibility, catalog UI,
and distribution polish remain deferred. See
[`docs/product/plans/phase-04-floating-pet.md`](docs/product/plans/phase-04-floating-pet.md) and the
[`phase-04 validation runbook`](docs/runbooks/phase-04-validation.md).

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

There is no npm publish yet. The CLI runs from source via Bun.

```bash
bun install
bun run packages/cli/bin/codogotchi.ts setup
```

`setup` prompts for your codogotchi **handle**, then **GitHub username** and **PAT**
(one after the other). Merged-PR signals only work when **both** are set; skipping
either leaves GitHub PR XP off until you fix it with `codogotchi config set` or
`setup --force`. Wakatime and GitHub credentials are optional.

Both binaries live under `packages/cli/bin/`. Wire them into your `PATH` (or
symlink them into `~/.local/bin/`) for convenience.

## CLI surface

```
codogotchi setup                              First-run config + hook install
codogotchi sync                               One sync cycle (all four sources)
codogotchi status                             Cached profile, HP, recent loot
codogotchi loot [--limit N] [--tier T]        Loot history from ~/.codogotchi/loot.log
codogotchi config get <key>                   Read a dotted config key
codogotchi config set <key> <value>           Write a typed value
codogotchi config list                        Full config as JSON (secrets redacted)
codogotchi vacation on [--until YYYY-MM-DD]   Pause HP decay
codogotchi vacation off                       Resume HP decay
codogotchi vacation status                    Show vacation state
```

Environment overrides:

| Var | Default | Effect |
| --- | --- | --- |
| `CODOGOTCHI_HOME` | `~/.codogotchi` | Config / cache / log root |
| `CODOGOTCHI_USER_ROOT` | OS home | Home dir used for hook installation |

## Where data lives

| Path | Owner | Purpose |
| --- | --- | --- |
| `~/.codogotchi/config.json` | `setup`, `config` | Credentials, health knobs, and pet name |
| `~/.codogotchi/profile.json` | `sync` | Local cache of Convex profile |
| `~/.codogotchi/state.json` | `codogotchi-hook` | Animation state for renderers (`schema_version: 2`) |
| `~/.codogotchi/app-state.json` | Codogotchi app | Floating pet visibility, position, size (`schema_version: 1`) |
| `~/.codogotchi/state-transitions.log` | Codogotchi app | NDJSON log of state changes and heartbeats |
| `~/.codogotchi/sync.log` | `sync` | Per-source success / failure (rotated) |
| `~/.codogotchi/loot.log` | `sync` (via Convex) | Loot history (for `loot`) |
| `~/.codogotchi/scorePR.log` | `sync` | `scorePR` heuristic decisions |
| `~/.codex/pets/<name>/` | user | Codex-sheet pet assets (`pet.json` + spritesheet) |
| `~/.codogotchi/pets/<name>/` | user | Codogotchi-sheet pet assets (`pet.json` + `codogotchi-spritesheet.webp`) |
| Convex `profiles`, `loot_events`, `users` | server | Canonical state |

## Health semantics

Three knobs in `~/.codogotchi/config.json`:

- `health.weekend_decay` — when `false` (default), HP does not drop Sat/Sun in
  the local timezone.
- `health.grace_days` — days of inactivity before HP starts decaying.
- `health.vacation_until` — ISO date through which HP decay is suspended; set
  via `codogotchi vacation on`.

## macOS app (Phase 04+)

The **Codogotchi** app (`apps/menubar/`) is an `LSUIElement` menu bar agent with
an optional float-on-top desktop pet. Build with `bun run mac:build`; validate
with [`docs/runbooks/phase-04-validation.md`](docs/runbooks/phase-04-validation.md).
Menu items include **Show/Hide Floating Pet**, **Open log folder**, **Reveal pet
folder**, and **Quit Codogotchi**. Demo mode (`CODOGOTCHI_DEMO=1`) drives both
surfaces from fixtures without touching live `state.json`.

## Pet configuration (Phase 03+)

The Codogotchi app resolves the active pet from `~/.codogotchi/config.json`:

```json
{ "pet": "maew" }
```

The `pet` key selects asset directories under `~/.codex/pets/<name>/` (Codex
sheet) and `~/.codogotchi/pets/<name>/` (codogotchi sheet). The compiled-in
default is `"maew"`. A missing, malformed, or `pet`-key-absent config falls
back to `"maew"` silently. The menu bar's **Reveal pet folder** item opens
`~/.codex/pets/` in Finder so you can inspect or swap the active pet.

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
