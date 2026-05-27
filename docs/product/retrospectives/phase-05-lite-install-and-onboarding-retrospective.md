# Phase 05 — Lite install and onboarding retrospective

Source plan: [`docs/product/plans/phase-05-lite-install-and-onboarding.md`](../plans/phase-05-lite-install-and-onboarding.md).
Delivery plan: [`docs/product/delivery/phase-05/implementation-plan.md`](../delivery/phase-05/implementation-plan.md).

## Scope delivered

Tickets P5.01 → P5.12 (12/12) shipped as a stacked PR chain on `agents/p5-*`
branches, PRs [#54](https://github.com/cesarnml/codogotchi/pull/54) through
[#65](https://github.com/cesarnml/codogotchi/pull/65) (final PR at closeout).
Delivered:

- Lite vs Alive config schema (`features.rpg_enabled`) and RPG command guards;
- TypeScript-owned `codogotchi hooks install | uninstall | status` with backup-then-merge;
- CLI split: `codogotchi setup` (Lite) vs `codogotchi rpg` (Alive enrollment);
- Bundled Maew + canonical `~/.codogotchi/pets/` store (no runtime `~/.codex/pets/` read);
- App bootstrap, `app-state.json`, subprocess hook status;
- Mandatory first-run onboarding sheet (consent, no skip, hooks-not-active until firing);
- Minimal Settings (Hooks, Pet, Alive stub);
- Operator backup/greenfield/restore scripts and developer config upgrade;
- Lite install runbook + README/status refresh;
- Menu **Reveal pet folder** → canonical path;
- Exit validation runbook and this retrospective.

## What went well

- **Config split early (P5.01 + P5.03) de-risked the whole phase.** Landing
  `rpg_enabled` and the `setup`/`rpg` command boundary before Swift UI work
  meant onboarding and Settings could assume Lite defaults without legacy
  Convex-in-setup branches in product code.
- **Hook policy centralized in TypeScript.** One merge/backup implementation
  shared by CLI, app subprocess, and docs avoided the drift we would have hit
  with duplicate Swift hook writers. The app's job stayed orchestration +
  honest status display.
- **Stack order matched product gates.** Maew/canonical store (P5.04) before
  onboarding (P5.06) and Settings (P5.07) meant UI tickets never had to fake
  pet paths or defer seeding logic.
- **Operator scripts as repo-only tooling.** Backup → greenfield → restore
  gave repeatable Lite validation without building a public migration wizard —
  appropriate for a single-operator repo.
- **Doc-only tickets at the end.** P5.10 runbook + P5.12 validation kept
  install truth in one place before the exit checklist, so README/status did
  not lag the app-first story mid-stack.

## Pain points

- **PATH dependency for app-first onboarding (expected cost).** The onboarding
  sheet subprocesses `codogotchi hooks install`; unsigned dev builds plus
  non-standard PATH layouts produced real "install failed" friction. Documented
  in the lite-install runbook, but bundling CLI in `.app` remains deferred.
- **Twelve stacked worktrees (avoidable friction).** Each ticket carried its
  own DerivedData build and mirrored delivery state. Gated boundary mode helped
  context hygiene but added resume overhead — acceptable for agent delivery,
  heavy for a human switching machines.
- **Subagent runner availability varied.** P5.02 recorded `skipped` when the
  programmatic runner was unavailable; policy allowed progress but reduced
  pre-PR adversarial coverage on a security-sensitive hooks ticket.

## Surprises

- **Cursor already animates via Claude bridge in dogfooding.** Phase 05 docs had
  to explain `source_origin: claude_code` with Cursor tool names as bridge
  behavior, not a Phase 05 bug — this was product truth discovered before
  Phase 06 native Cursor hooks.
- **`hooks install` refusing without config forced bootstrap ordering.** App
  first launch must write Lite config before hooks; `setup` and app bootstrap
  both seed home — a constraint that was implicit in grill-me but showed up
  again in integration tests.
- **Doc-only P5.09 still mattered for operator exit.** "Developer machine"
  upgrade was not user-facing, but Gate 4 (operator RPG preserved) depended on
  it; treating operator tickets as optional would have broken the stated exit
  condition.

## What we'd do differently

- **Earlier cross-link from README to runbook at P5.10 start, not P5.12.**
  Mid-stack readers on `main` still saw Phase 04–era status until P5.10; we
  would bump README status when P5.06 onboarding lands, not at closeout.
- **Single validation scratch doc during delivery.** P5.12 validation runbook
  consolidates exit checks, but recording pass/fail per gate (G1–G4) during
  the stack would have made closeout attestation faster.
- **Stronger partial-failure messaging on `setup` + `installHooks`.** Subagent
  review on P5.03 flagged config-on-disk with failed hook install; a clearer
  recovery string would reduce retry confusion (low severity, easy follow-up).

## Net assessment

Phase 05 achieved its stated goal: Codogotchi is now a **Lite-first** macOS
desktop pet after local install, with app-first hook consent, canonical Maew
assets, honest Cursor bridge copy, and Alive (RPG) as an explicit opt-in via
`codogotchi rpg`. The primary onboarding boundary moved from CLI-first Convex
enrollment to app-first hook install without shipping App Store distribution or
native multi-IDE installers. Operator RPG behavior is preserved via scripts and
the config upgrade path. The architecture (TS hook policy, canonical pet store,
`app-state.json` for UI, subprocess status JSON) is stable for Phase 06 signal
honesty and Phase 10 Settings depth.

## Follow-up

- Run [`docs/runbooks/phase-05-validation.md`](../../runbooks/phase-05-validation.md)
  on the owner's machine before `closeout-stack` and record pass/fail.
- Phase 06: native Cursor hooks + honest `source_origin`; do not extend Lite
  onboarding to claim native Cursor install until that lands.
- Consider bundling or embedding CLI for distribution after Phases 05–14; until
  then keep PATH prerequisites prominent in install docs.
- Optional CLI polish: clearer recovery when `setup` writes config but
  `hooks install` fails (P5.03 subagent note).

_Created: 2026-05-28. PR #66 open at delivery time._
