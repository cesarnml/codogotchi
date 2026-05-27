# Phase 05 Lite install runbook

Codogotchi ships as a **source build** — no App Store, no notarized DMG. This runbook covers the full install path from a fresh checkout to a running pet that reacts to real tool events.

**Scope:** Lite mode. Maew idles and fires on Claude Code / Codex activity. RPG features (XP, Convex sync, loot) require a separate `codogotchi rpg` enrollment step — see the [Lite vs Alive](#lite-vs-alive) section below.

**Not in scope:** Mac App Store submission, notarization, VS Code hooks, native Cursor hooks, in-app RPG enrollment, HP overlays, loot UI. These are deferred to later phases.

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

The debug build (from `bun run mac:build`) is fine for development. For a persistent desktop install use a Release archive:

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

For development iteration the debug build works too — find it under Xcode DerivedData:

```bash
find ~/Library/Developer/Xcode/DerivedData -name 'Codogotchi.app' -path '*/Build/Products/*' | head -1
```

---

## Step 3 — First launch + onboarding consent

Open the app:

```bash
open /Applications/Codogotchi.app
```

On first launch the app writes a minimal Lite config at `~/.codogotchi/config.json` (if none exists), then presents the **Welcome to Codogotchi** onboarding sheet.

The sheet explains that Codogotchi installs itself into your Claude Code and Codex hook configs. There is **no skip** — the CTA reads **Approve & install hooks**. Clicking it runs:

```bash
codogotchi hooks install
```

This backs up any existing hook JSON before writing, so existing hooks are preserved.

> **Gatekeeper first launch:** unsigned dev builds require right-click → **Open** the first time. Click **Open** in the dialog that appears.

---

## Step 4 — Verify hook install

After the sheet closes, check hook status from the CLI:

```bash
codogotchi hooks status
```

Expected output shows `installed: true` and `firing_recently: false` for `claude_code` and/or `codex` (Cursor, VS Code, and Antigravity report `installable_in_phase: false` — these are Phase 06 targets).

---

## Step 5 — Confirm idle → firing transition

Trigger a real tool event:

1. Use Claude Code for a few turns (any tool call fires the hook).
2. Watch the menu bar pet — it should transition from idle to one of the activity states (implementing, running-tests, reviewing, etc.) within seconds.

Check status again to confirm:

```bash
codogotchi hooks status
```

`firing_recently: true` on at least one platform confirms the full pipeline is live.

---

## Cursor via Claude bridge

Cursor users can route activity through **Claude Code** using a third-party skill. The hook fires with `source_origin: claude_code` and Cursor-originated tool names pass through unchanged. This is the supported bridge in Phase 05.

**Native Cursor hooks** (`source_origin: cursor`) are deferred to Phase 06. `codogotchi hooks status` will show `cursor.installable_in_phase: false` and `source_origin: "phase-06-deferred"` to make this explicit.

---

## Demo mode (developer QA only)

Demo mode drives both the menu bar micro-pet and the floating desktop pet from a fixture state cycle without touching live `~/.codogotchi/state.json`. It is **not** a user-facing Lite path.

```bash
CODOGOTCHI_DEMO=1 open /Applications/Codogotchi.app
# or via launch argument:
/Applications/Codogotchi.app/Contents/MacOS/Codogotchi --demo
```

Do not present `--demo` or `CODOGOTCHI_DEMO=1` as an install option in user-facing copy.

---

## Operator scripts

The operator scripts in `scripts/operator/` support the RPG ↔ Lite transition on a developer machine. See [`docs/runbooks/phase-05-operator.md`](phase-05-operator.md) for the full workflow:

- `scripts/operator/backup-rpg-home.sh` — non-destructive backup of `~/.codogotchi`
- `scripts/operator/enter-lite-greenfield.sh` — backup + wipe to start fresh
- `scripts/operator/restore-rpg-home.sh` — restore from an existing backup
- `scripts/operator/upgrade-phase-05-config.ts` — add `features.rpg_enabled: true` to a pre-Phase 05 config

---

## Uninstall hooks

```bash
codogotchi hooks uninstall
```

This removes Codogotchi entries from Claude Code and Codex hook configs. Existing hook files are preserved; only the Codogotchi entries are removed.

---

## Exit validation

Before phase closeout, run the full exit checklist in
[`phase-05-validation.md`](phase-05-validation.md) (greenfield install, onboarding,
Settings, CLI Lite/RPG, operator round-trip, deferrals).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Onboarding sheet won't close | Hook install failed | Check that `codogotchi` is on PATH; retry via **Retry install** button |
| `hooks status` shows `installed: false` | PATH not available to app | Ensure `codogotchi` is in `/usr/local/bin` or `/opt/homebrew/bin` |
| Pet stays idle after tool use | Hook not firing | Confirm `firing_recently: true`; check `~/.codogotchi/state.json` mtime |
| App shows no menu bar icon | `LSUIElement` agent started but crashed | Check Console.app for crash logs from `Codogotchi` |
