# Phase 05 — Lite Install And Onboarding

> Make Codogotchi a standalone macOS desktop pet after local install: bundled Maew, app-first hook consent, Lite default config, RPG opt-in. Twelve tickets, ~27 points, five stage gates.

## Epic

Source product plan: [`docs/product/plans/phase-05-lite-install-and-onboarding.md`](../../plans/phase-05-lite-install-and-onboarding.md).

## Product Contract

When this phase is complete:

- After documented local install (Xcode Release → `/Applications` or runbook), the app shows **Maew** idle animation without `~/.codex/pets/` and without Convex enrollment.
- First-run onboarding explains hooks, requires **Approve & install** (no skip), backs up Codex/Claude hook JSON before write, and keeps **Hooks not active** until install succeeds and hook-driven activity is observed.
- Minimal Settings exposes Hooks (install/uninstall/status), Pet (canonical store + optional import from `~/.codex/pets/*`), and Alive stub (`codogotchi rpg`).
- `codogotchi setup` is **Lite** (minimal config + `hooks install`); `codogotchi rpg` is **Alive** enrollment; `codogotchi hooks install | uninstall | status` is the single hook policy surface.
- Greenfield Lite config omits RPG fields; `sync` and other RPG commands refuse when `features.rpg_enabled === false`.
- Hook install policy lives in TypeScript only; the macOS app invokes `codogotchi hooks …` via subprocess.
- Runtime pet root is `~/.codogotchi/pets/` only; Maew is bundle-seeded with `pet.json`, `spritesheet.webp`, and `codogotchi-spritesheet.webp`.
- Operator can round-trip **backup → Lite greenfield → restore RPG** via repo scripts; final operator ticket upgrades the developer config to `rpg_enabled: true` without product migration wizards.
- README/runbook document local install and Cursor-via-Claude-bridge honesty (native Cursor hooks → Phase 06).
- **No user-facing demo mode** — `--demo` remains developer QA only.

## Grill-Me Decisions Locked

- **Q1 — Hook policy in TypeScript.** `packages/cli` owns merge/backup/uninstall; app and Settings subprocess `codogotchi hooks …`. PATH is acceptable for Phase 05; bundling CLI in `.app` is deferred to App Store distribution work.
- **Q2 — Canonical pet store only.** Loaders read `~/.codogotchi/pets/<pet>/`; first launch seeds Maew from app bundle (Codex grid + codogotchi sheet). No runtime read from `~/.codex/pets/`.
- **Q3 — Minimal Lite config.** Greenfield writes `{ profile_id, pet: "maew", features: { rpg_enabled: false } }` only; RPG keys appear after `codogotchi rpg`. No implicit legacy branches in product code.
- **Q4 — Idle, not demo.** Pet animates idle from seeded assets; no user-facing demo carousel; dev `--demo` stays QA-only.
- **Q5 — No skip on hooks.** Onboarding is consent to touch other apps' configs, not optional hooks; persistent CTA until install works and activity is observed.
- **Q6 — `hooks` subcommand group.** `install | uninstall | status` shared by CLI, app, and docs.
- **Q7 — Bootstrap ownership.** App first launch and `codogotchi setup` seed `~/.codogotchi/`; `hooks install` refuses if home/config is missing.
- **Q8 — Operator upgrade script.** Repo-only `scripts/operator/` upgrade path; no public `codogotchi migrate`.
- **Q9 — Greenfield test scripts.** `backup-rpg-home`, `enter-lite-greenfield`, `restore-rpg-home`; Lite does not report to Convex; full home backup preserves local RPG artifacts.
- **Q10 — UI state in `app-state.json`.** Onboarding completion and hook-activity timestamps extend app-state; `hooks status` JSON from TS remains authoritative for install/firing truth.
- **Stage gates are markers, not orchestrator stops.**
- **Retrospective:** `required`. Trigger: primary onboarding boundary change (CLI-first → app-first), hook consent/backup, cross-platform copy honesty.

## Ticket Order

| Order | ID | Title | Pts | Type | Scope | Red |
|-------|-----|--------|-----|------|-------|-----|
| 1 | P5.01 | Lite/RPG config schema + CLI guards | 2 | feat | cli-config | required |
| 2 | P5.02 | `hooks install \| uninstall \| status` | 3 | feat | hooks | required |
| 3 | P5.03 | CLI `setup` / `rpg` split | 3 | feat | cli | required |
| 4 | P5.04 | Bundled Maew + canonical pet store | 3 | feat | pet-store | required |
| 5 | P5.05 | App bootstrap + app-state + `hooks status` | 2 | feat | app-state | required |
| 6 | P5.06 | First-run onboarding sheet | 3 | feat | onboarding | required |
| 7 | P5.07 | Minimal Settings window | 3 | feat | settings | required |
| 8 | P5.08 | Operator scripts (upgrade + greenfield) | 2 | chore | operator | skip |
| 9 | P5.09 | Operator config upgrade (developer machine) | 1 | chore | operator | skip |
| 10 | P5.10 | Lite install runbook + README | 2 | docs | runbooks | skip |
| 11 | P5.11 | Reveal pet folder → canonical path | 1 | fix | menubar-menu | required |
| 12 | P5.12 | Exit validation runbook + retrospective | 2 | docs | product | skip |

## Ticket Files

- `ticket-01-lite-rpg-config-schema-and-cli-guards.md`
- `ticket-02-hooks-install-uninstall-status.md`
- `ticket-03-cli-setup-rpg-split.md`
- `ticket-04-bundled-maew-canonical-pet-store.md`
- `ticket-05-app-bootstrap-app-state-hooks-status.md`
- `ticket-06-first-run-onboarding-sheet.md`
- `ticket-07-minimal-settings-window.md`
- `ticket-08-operator-scripts.md`
- `ticket-09-operator-config-upgrade.md`
- `ticket-10-lite-install-runbook-and-readme.md`
- `ticket-11-reveal-pet-folder-canonical-path.md`
- `ticket-12-exit-validation-retrospective-doc-sweep.md`

## Exit Condition

All exit conditions from the product plan are demonstrably true:

1. Clean machine (or greenfield script state): local install → launch → Maew idle without prior `~/.codogotchi/` or `~/.codex/pets/`.
2. First-run onboarding: hooks explained, consent, backup-then-install for Codex and/or Claude Code; no skip.
3. Hooks not active until install succeeds and pet reacts to real events (**firing recently**).
4. Minimal Settings can install/uninstall hooks and shows per-platform status with honest Cursor bridge copy in docs.
5. `codogotchi setup` / `codogotchi rpg` / `codogotchi hooks …` behave per product table; Lite does not call Convex via RPG commands.
6. Operator: `rpg_enabled: true` after P5.09; greenfield round-trip via P5.08 scripts without losing RPG progress on restore.
7. App Store, native Cursor installer, in-app RPG enroll, user demo, and Convex schema changes remain absent by design.

## Stage Gates

- **Gate 1 (after P5.04).** Maew loads from canonical store only; app launches with idle pet and no `~/.codex/pets/` dependency.
- **Gate 2 (after P5.03).** CLI Lite/RPG/hooks surface matches product table.
- **Gate 3 (after P5.07).** App-first onboarding + Settings E2E on a greenfield home.
- **Gate 4 (after P5.09).** Operator RPG preserved; greenfield scripts verified on developer machine.
- **Gate 5 (after P5.12).** Exit validation runbook + retrospective complete.

## CI Baseline

> Baseline recorded: 2026-05-27 — **pass** (`bun run ci:quiet`, including `bun run mac:test` — 164 tests, 0 failures).

Run `bun run ci:quiet` on `main` before P5.01 starts if this snapshot is stale.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass `bun run ci:quiet` before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Tickets with `Red: required` follow red-green-refactor on the branch before merge.
- Tickets with `Red: skip` are structurally doc/chore-only for Red; human review is the gate.
- Swift behavior tickets use `bun run mac:test`; CLI tickets use `bun test` for touched packages.
- Subagent review per `orchestrator.config.json` `skip_doc_only`: P5.01–P5.07 and P5.11 receive subagent review; P5.08–P5.10 and P5.12 skip when doc/chore-only.

## Explicit Deferrals

- Mac App Store submission, notarization for store, Apple Developer Program enrollment.
- Native Cursor, VS Code, and Antigravity hook installers; honest `source_origin: cursor` (Phase 06).
- Full Settings tabs and in-app RPG enrollment (Phase 10).
- User-facing demo mode; menu/README must not present demo as a Lite path.
- Attention tray, signal honesty, HUD, health visuals, loot UI, Convex schema changes.
- Bundling `codogotchi` CLI inside `.app` for PATH-free install (distribution milestone after Phases 05–14).

## Stop Conditions

- Maew Codex-grid `spritesheet.webp` cannot be added to the app bundle (blocks Gate 1).
- macOS app cannot subprocess `codogotchi hooks install` reliably (permissions/PATH) without a documented fallback — stop and decide bundle-in-app vs blocking onboarding.
- Swift cannot honor `CODOGOTCHI_HOME` for pet/config/app-state paths needed by greenfield scripts — stop and unify path resolution before UI tickets.
- Hook backup/merge cannot be made idempotent with existing P1.12 tests without redesign — stop and narrow P5.02 scope with developer input.

## Phase Closeout

Retrospective: required  
Why: Phase 05 changes the primary onboarding boundary (CLI-first → app-first) and hook consent model; durable learnings on backup, cross-platform copy, and Lite vs RPG split.  
Trigger: Developer approval of P5.12 merge.  
Artifact: `docs/product/retrospectives/phase-05-lite-install-and-onboarding-retrospective.md`
