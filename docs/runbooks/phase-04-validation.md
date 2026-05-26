# Phase 04 validation runbook

Phase 04 is "done" when the owner can launch **Codogotchi**, use the menu bar micro-pet and the transparent floating desktop pet together, drag and resize the floating pet between documented bounds, survive quit/relaunch with placement restored, recover from invalid saved frames after display changes, and watch both surfaces agree on the same live or demo activity state.

This runbook is a **single local session** — one pass through the checklist below. Screenshots and screen recordings are **optional** evidence; notes in a scratch file or PR comment are enough.

**Out of scope for this runbook:** HP overlays, XP bars, stage indicators, loot UI, focus-aware visibility, pet picker/catalog, distribution polish, and public launch assets. Those remain deferred.

---

## Prerequisites

1. **Build the app** from the repo root (see [`apps/menubar/README.md`](../apps/menubar/README.md)):

   ```bash
   bun run mac:build
   ```

   The product is `Codogotchi.app` under Xcode DerivedData. Find it with:

   ```bash
   find ~/Library/Developer/Xcode/DerivedData -name 'Codogotchi.app' -path '*/Build/Products/*' | head -1
   ```

   Export a shell alias for the rest of this session:

   ```bash
   export CODOGOTCHI_APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'Codogotchi.app' -path '*/Build/Products/*' | head -1)"
   ```

2. **Pet assets** — confirm the active pet from `~/.codogotchi/config.json` has both sheets:

   ```bash
   jq -r '.pet' ~/.codogotchi/config.json
   ls ~/.codex/pets/<pet>/
   ls ~/.codogotchi/pets/<pet>/
   ```

   You need the Codex spritesheet under `~/.codex/pets/<pet>/` and `codogotchi-spritesheet.webp` under `~/.codogotchi/pets/<pet>/`. If either is missing, demo mode still exercises plumbing but reserved mouse rows may fall back to idle.

3. **Gatekeeper** — first launch of an unsigned dev build may require right-click → **Open** once. See the menubar README for the usual macOS exception flow.

4. **Optional demo isolation** — to avoid touching live `~/.codogotchi/state.json`, run demo mode for state-sync checks:

   ```bash
   CODOGOTCHI_DEMO=1 open "$CODOGOTCHI_APP"
   ```

   Demo cycles activity states on a timer; both menu bar and floating surfaces should stay in agreement.

---

## Checklist

Work top to bottom. Mark each row **pass / fail / skip (reason)**.

| # | Check | How | Pass |
|---|-------|-----|------|
| 1 | App identity | Launch `open "$CODOGOTCHI_APP"`. Click the menu bar icon. | Menu title reads **Codogotchi**; **Quit Codogotchi** is present. Dock icon stays hidden (LSUIElement agent). |
| 2 | Menu bar pet alive | With the app running, watch the status item for a few seconds (or run demo mode). | Pet animates or holds a non-crashing idle pose; no repeated crash loops. |
| 3 | Show floating pet | Menu → **Show Floating Pet**. | Transparent float-on-top pet appears near the **bottom-right** of the active display (default ~160×160 pt, 24 pt margin). |
| 4 | Hide floating pet | Menu → **Hide Floating Pet**. | Floating surface disappears; menu bar pet remains. Toggle show again before continuing. |
| 5 | Drag | Click-hold the pet body (not the corner affordance) and drag to a new location. Release. | Panel moves smoothly; position updates while dragging. |
| 6 | Resize min | Click-hold the **bottom-right resize affordance** and shrink until movement stops. | Size stops at **96×96 pt** minimum (`FloatingFramePolicy.minimumSize`). |
| 7 | Resize max | From minimum, drag the affordance outward until movement stops. | Size stops at **512×512 pt** maximum (`FloatingFramePolicy.maximumSize`). |
| 8 | Resize cursor | Hover the affordance without dragging. | Cursor switches to a horizontal resize cursor when macOS allows it. |
| 9 | Quit/relaunch persistence | Move and resize to a non-default frame. Quit (**Quit Codogotchi**). Relaunch. | Floating pet reappears at the saved position and size. Confirm file updated: `cat ~/.codogotchi/app-state.json` shows `floating_pet.visible` and frame coordinates matching what you set. |
| 10 | Display fallback | With the pet visible, disconnect an external monitor or change resolution so the saved frame would land off-screen (or edit `app-state.json` to absurd coordinates, then relaunch). | App reclamps to a **visible safe frame** on the current display instead of opening off-screen. |
| 11 | Demo/live state sync | Run `CODOGOTCHI_DEMO=1 open "$CODOGOTCHI_APP"` (or trigger live hook activity). Watch menu bar and floating pet together for ≥30 s. | Both surfaces show the **same** activity state at each transition (no long-lived divergence). |
| 12 | Reserved mouse rows | While dragging horizontally, glance at the floating animation; hover/drag the resize affordance. | Drag left/right may show Codex **running-left** / **running-right** rows when the active Codex sheet supports them; resize affordance may show **jumping**. If the active asset lacks a row, graceful idle fallback is acceptable — note **skip (asset)** rather than **fail**. |

---

## Quick reference

| Topic | Location / value |
|-------|------------------|
| Activity state | `~/.codogotchi/state.json` (or demo sandbox under `$TMPDIR/codogotchi-demo/`) |
| Floating placement | `~/.codogotchi/app-state.json` (`schema_version: 1`) |
| Pet selection | `~/.codogotchi/config.json` |
| Size bounds | 96×96 … 512×512 pt |
| Default floating size | 160×160 pt, bottom-right with 24 pt margin |
| Transition log | `tail -f ~/.codogotchi/state-transitions.log` |
| Build/test | `bun run mac:build`, `bun run mac:test` |
| Phase plan exit conditions | [`docs/product/plans/phase-04.md`](../product/plans/phase-04.md) |

---

## Optional evidence (not required)

If you want a paper trail without a screenshot packet:

- Paste `jq` output for `~/.codogotchi/app-state.json` before and after the persistence check.
- Note the DerivedData path and git SHA you built from.
- For row 12, one sentence on which reserved rows you saw (or why the asset skipped them).

---

## Explicit non-goals

Do **not** treat absence of the following as Phase 04 failures during this runbook:

- HP hearts, ghost/death visuals, mood tints
- XP bars, stage indicators, loot moments
- Focus-aware auto-hide when Codex/Claude is not frontmost
- Pet catalog, picker UI, multi-pet matrix validation
- Signed/notarized install, Sparkle updates, launch-at-login automation
- Public README GIFs or marketing capture

Those belong to later phases per [`docs/product/plans/phase-04.md`](../product/plans/phase-04.md#explicit-deferrals).
