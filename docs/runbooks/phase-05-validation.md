# Phase 05 validation runbook

Phase 05 is "done" when a greenfield or operator-reset machine can install Codogotchi locally, see **Maew** idle without `~/.codex/pets/`, complete mandatory hook onboarding (consent + backup-then-install, no skip), observe **firing recently** after real tool use, use minimal Settings for hooks/pet/Alive stub, and run the Lite vs Alive CLI surface without `setup` implying RPG enrollment.

This runbook is a **single local session** — one pass through the checklist below. Screenshots are optional; pass/fail notes in a scratch file or PR comment are enough.

**Companion docs:**

- Install walk-through: [`phase-05-lite-install.md`](phase-05-lite-install.md)
- Operator RPG ↔ Lite scripts: [`phase-05-operator.md`](phase-05-operator.md)

**Out of scope for this runbook:** Mac App Store submission, native Cursor/VS Code/Antigravity hook installers, in-app RPG enrollment UI, user-facing demo mode, HP/XP/loot HUD, Convex schema changes.

---

## Prerequisites

1. **Build and PATH** — from repo root:

   ```bash
   bun install
   bun run mac:build
   ```

   Wire CLI binaries into PATH (onboarding subprocesses `codogotchi hooks …`):

   ```bash
   export PATH="$PWD/packages/cli/bin:$PATH"
   command -v codogotchi && command -v codogotchi-hook
   ```

   Release install to `/Applications` (optional but matches exit-condition hero path):

   ```bash
   # See phase-05-lite-install.md Step 2 for xcodebuild archive/export
   export CODOGOTCHI_APP="/Applications/Codogotchi.app"
   ```

   For DerivedData-only dev builds:

   ```bash
   export CODOGOTCHI_APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'Codogotchi.app' -path '*/Build/Products/*' | head -1)"
   ```

2. **Greenfield home (checks 1–5)** — use a fresh `CODOGOTCHI_HOME` or operator script:

   ```bash
   bash scripts/operator/enter-lite-greenfield.sh
   ```

   Confirm `~/.codogotchi` is absent (or use a temp home):

   ```bash
   test ! -e ~/.codogotchi/config.json && echo "greenfield ok"
   ```

3. **Operator RPG home (checks 6–7)** — after greenfield checks, restore operator backup and confirm `features.rpg_enabled: true` (see [`phase-05-operator.md`](phase-05-operator.md)).

---

## Checklist — greenfield / Lite hero path

Work top to bottom. Mark each row **pass / fail / skip (reason)**.

| # | Check | How | Pass |
|---|-------|-----|------|
| 1 | Clean install → Maew idle | `open "$CODOGOTCHI_APP"` with no prior `~/.codogotchi/` and no `~/.codex/pets/` dependency. | Menu bar pet shows Maew idle animation; no crash loop. `ls ~/.codogotchi/pets/maew/` shows `pet.json`, `spritesheet.webp`, `codogotchi-spritesheet.webp` seeded from bundle. |
| 2 | Lite config shape | `cat ~/.codogotchi/config.json` | Contains `profile_id`, `pet` (default `maew`), `features.rpg_enabled: false`. No required `handle` or `convex_http_url` for Lite. |
| 3 | Onboarding consent, no skip | First-run sheet: read copy, click **Approve & install hooks**. | Sheet explains hooks; no skip/dismiss path. Backups created for Codex/Claude hook JSON before write (timestamped sidecar under tool config dirs). |
| 4 | Hooks not active → firing | Before install: status shows not firing. After install: run Claude Code or Codex for a few tool calls. | Pet transitions off idle; `codogotchi hooks status` shows `firing_recently: true` on at least one installable platform. Onboarding/sheet clears **Hooks not active** when firing is observed. |
| 5 | Settings hooks path | Open minimal Settings → Hooks. Install/uninstall/status. | Per-platform rows for Codex + Claude Code; Cursor shows honest bridge/deferred copy (`installable_in_phase: false` or equivalent). Install from Settings works when hooks were removed. |
| 6 | Cursor bridge copy | Read README § Cursor, onboarding copy, or `codogotchi hooks status --json` for `cursor`. | Docs explain Claude third-party bridge vs native `~/.cursor/hooks.json` (native install shipped Phase 06; bridge still valid). |
| 7 | CLI Lite vs Alive | Greenfield: `codogotchi setup` → inspect config. `codogotchi sync` before RPG. Then `codogotchi rpg` (or restore operator config). | `setup` writes Lite + installs hooks; `sync` refuses with message pointing to `rpg`. After `rpg` or operator upgrade: `sync` succeeds. `codogotchi hooks install\|uninstall\|status` behave per product table. |
| 8 | Reveal pet folder | Menu → **Reveal pet folder**. | Finder opens `~/.codogotchi/pets/` (canonical store), not `~/.codex/pets/`. |
| 9 | No user-facing demo | Scan README + onboarding; do not document `--demo` as install path. | Demo mentioned only as developer QA (`CODOGOTCHI_DEMO=1` / `--demo`). Optional: run demo and confirm it does not write live `state.json`. |
| 10 | Operator greenfield round-trip | `backup-rpg-home.sh` → `enter-lite-greenfield.sh` → exercise Lite → `restore-rpg-home.sh` → `codogotchi sync`. | RPG progress and config restored; `jq '.features.rpg_enabled' ~/.codogotchi/config.json` is `true` after restore/upgrade. |
| 11 | Operator config upgrade | On a pre-Phase-05-shaped backup (or dry-run): `bun scripts/operator/upgrade-phase-05-config.ts --dry-run` then apply. | Adds `features.rpg_enabled: true` without dropping handle/GitHub/Convex fields. |
| 12 | Explicit deferrals absent | Skim app Settings and public docs. | No App Store install path, no native Cursor installer, no in-app RPG enroll wizard, no Convex schema/UI changes claimed as shipped. |

---

## Quick reference

| Topic | Location / command |
|-------|-------------------|
| Lite install | [`phase-05-lite-install.md`](phase-05-lite-install.md) |
| Operator scripts | [`phase-05-operator.md`](phase-05-operator.md) |
| Animation state | `~/.codogotchi/state.json` |
| App UI state | `~/.codogotchi/app-state.json` |
| Canonical pets | `~/.codogotchi/pets/<id>/` |
| Hook policy | `codogotchi hooks install \| uninstall \| status [--json]` |
| Lite entry | `codogotchi setup` or first app launch |
| Alive entry | `codogotchi rpg` |
| Transition log | `tail -f ~/.codogotchi/state-transitions.log` |
| Build/test gate | `bun run ci:quiet` |
| Product plan exit | [`docs/product/plans/phase-05-lite-install-and-onboarding.md`](../product/plans/phase-05-lite-install-and-onboarding.md#exit-condition) |

---

## Optional evidence (not required)

- Paste `jq` output for `config.json` after `setup` and after `rpg`.
- Note git SHA and `CODOGOTCHI_APP` path used.
- One line on which platform showed `firing_recently: true`.

---

## Explicit non-goals

Do **not** treat absence of the following as Phase 05 failures during this runbook:

- Mac App Store / notarized distribution
- Native VS Code Copilot or Antigravity hook files with honest `source_origin` (Phase 09; Cursor native hooks shipped Phase 06)
- Full Settings tabs, in-app RPG enrollment, HP/XP/stage/loot visuals
- Bundled `codogotchi` inside `.app` without PATH
- Public demo carousel or `--demo` as a Lite onboarding path

Those belong to later phases per [`docs/product/plans/phase-05-lite-install-and-onboarding.md`](../product/plans/phase-05-lite-install-and-onboarding.md#explicit-deferrals).
