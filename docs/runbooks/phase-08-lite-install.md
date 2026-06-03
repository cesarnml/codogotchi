# Phase 08 Lite install runbook

> **Historical.** Phase 10 shipped **Free RPG (local)** as the product direction. See [README](../../README.md) for current tiers; use this runbook for bundled `.app` install mechanics.

Codogotchi ships as a **source build** — no App Store, no notarized DMG. This runbook covers the
full install path from a fresh checkout to a running pet that reacts to real tool events.

**What's new in Phase 08:** The `.app` bundles its own `codogotchi` binary. No PATH prerequisite.
Hook install, update, and remove live in **Settings → General** only — no Terminal steps.

---

## Prerequisites

- macOS 13+ (tested on Sequoia)
- Xcode (with the macOS SDK — a command-line-only toolchain is not sufficient)
- Bun ≥ 1.0 (`brew install bun`)
- Claude Code and/or Codex installed and used regularly

---

## Step 1 — Clone and install deps

```bash
git clone <repo>
cd codogotchi
bun install
```

---

## Step 2 — Release build + install to `/Applications`

The debug build (from `bun run mac:build`) is fine for development. For a persistent desktop install
use a Release archive:

```bash
xcodebuild \
  -project apps/menubar/Codogotchi.xcodeproj \
  -scheme Codogotchi \
  -configuration Release \
  -archivePath /tmp/Codogotchi.xcarchive \
  archive

xcodebuild \
  -exportArchive \
  -archivePath /tmp/Codogotchi.xcarchive \
  -exportPath /tmp/CodogotchiExport \
  -exportOptionsPlist apps/menubar/ExportOptions.plist

cp -R "/tmp/CodogotchiExport/Codogotchi.app" /Applications/
```

No `codogotchi` on PATH required — the app uses its bundled binary.

---

## Step 3 — First launch + onboarding consent

Open the app:

```bash
open /Applications/Codogotchi.app
```

On first launch the app:
1. Seeds the bundled Maew assets to `~/.codogotchi/pets/maew/`.
2. Presents the **Welcome to Codogotchi** onboarding sheet.

The sheet explains that Codogotchi installs itself into your Claude Code and Codex hook configs.
There is **no skip** — click **Approve & install hooks**. This backs up any existing hook JSON
before writing.

> **Gatekeeper first launch:** unsigned dev builds require right-click → **Open** the first time.

---

## Step 4 — Verify hook install

After the sheet closes, check hook status from **Settings → Developer** (Hooks section), or from
the CLI:

```bash
codogotchi hooks status
```

Expected output: `claude_code: installed`, `codex: installed`.

---

## Step 5 — Confirm idle → firing transition

Trigger a real tool event:

1. Use Claude Code for a few turns (any tool call fires the hook).
2. Watch the menu bar pet — it should transition from idle to an activity state within seconds.

---

## Ongoing hook management

Use **Settings → General** (menu bar → **Settings…** → General tab) to:

- **Install hooks** — writes hook entries to Claude Code + Codex (or Cursor with --platform cursor).
- **Update hooks** — re-runs install against the bundled binary path; run after app updates.
- **Remove hooks** — removes Codogotchi entries from hook JSON files.

No Terminal commands needed for normal hook management.

---

## Pet selection

Use **Settings → Pet** to:

- View all pets (bundled Maew + Codex pets from `~/.codex/pets/` + previously imported pets).
- Select the active pet (persists to `~/.codogotchi/config.json`).
- Import a Codex pet into the canonical store (`~/.codogotchi/pets/<id>/`).

---

## Lite vs Alive

| Mode | How to enter | Convex sync | XP / Loot |
|---|---|---|---|
| **Lite** | First app launch | No | No |
| **Alive (RPG)** | `codogotchi rpg` (CLI, until Phase 10 ships in-app enrollment) | Yes | Yes |

Run `codogotchi rpg` to enroll and enable RPG features.
