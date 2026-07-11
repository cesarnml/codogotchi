# P16.07 Closeout: exit audit + dogfood DMG + retrospective

Size: 2 points
Type: chore
Scope: menubar
Red: skip

## Outcome

- All seven phase exit conditions are audited on `v3_preview` with evidence (command + output) recorded in this ticket's Rationale section.
- A dogfood DMG is packaged via `scripts/package-dmg.sh` and installed as the daily driver.
- **No version bump, no GitHub release, no download-page change** — local-only artifact per the product plan; the macOS release ritual is deliberately not followed beyond packaging.
- The Phase 16 retrospective exists at `docs/product/retrospectives/phase-16-mechanical-consolidation-retrospective.md`.

## Exit audit checklist (run each, record evidence)

1. **Drawers:** `find apps/menubar/Sources -maxdepth 1 -name '*.swift'` → empty; xcodegen build green.
2. **Splits:** `FloatingPetPanel.swift` and `SettingsWindowController.swift` absent from the tree.
3. **WindowKey kill list:** `grep -rn '"combined"' apps/menubar/Sources` → only WindowKey parse/serialize + persistence boundaries; colon-split grep clean.
4. **Lifecycle:** `SessionLifecycle` classifier is the only lifecycle-judgment site; both consumers match on it.
5. **One writer:** exactly one `customization.json` write site.
6. **Behavior bar:** full suite green; `bun run verify` and `bun run ci:quiet` pass.
7. **Dogfood:** DMG packaged, installed, running as daily driver.

## Red

- `Red: skip` — audit + packaging + docs; no testable behavior added.

## Green

- Run the audit checklist; paste evidence into Rationale.
- Package the DMG; install; confirm the installed app runs against live state.
- Write the retrospective using the `soa-write-retrospective` skill.

## Refactor

- None. If any audit item fails, the fix belongs in a reopened prior ticket's scope or a separate bug-fix commit with a review-gap ledger entry — not in this ticket.

## Review Focus

- Evidence is real command output, not paraphrase.
- No release-ritual leakage: Info.plist / project.yml / download.astro untouched; no `gh release` artifacts.
- Retro captures drawer-taxonomy and domain-type decisions Phases 17–18 inherit, and any review-gap ledger entries produced during the phase.
- The Phase 17 soak gate is recorded as a phase-transition condition in the implementation plan — not marked satisfied by this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (`Red: skip` — audit/packaging/docs)
Why this path: cross-ticket invariants need one authoritative audit after the last code ticket
Alternative considered: folding the audit into P16.06 — rejected; invariants can regress after their originating ticket
Deferred: Phase 17 soak-gate satisfaction (phase-transition condition, not ticket work); any public release (Track 2)
