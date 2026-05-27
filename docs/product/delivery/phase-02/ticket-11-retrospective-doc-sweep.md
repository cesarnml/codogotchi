# P2.11 Retrospective + doc-drift sweep + swift-notes INDEX

Size: 1 point
Type: docs
Scope: phase-02
Red: skip

## Outcome

- `docs/product/retrospectives/phase-02-macos-menu-bar-pet-retrospective.md` lands per the `soa-write-retrospective` skill's structure (section conventions live in that skill, not duplicated here). The retro covers:
  - What worked.
  - What bit (especially Swift-newbie surprises, Xcode-project quirks, AppKit gotchas, WebP loading wrinkles).
  - **Phase 01 patches surfaced during live use** — a dedicated subsection cross-linking any standalone PRs to `main` that landed during Phase 02's live-integration / hardening stages. Lists PR numbers, titles, and what they fixed. If no patches were needed, the section explicitly states "No Phase 01 patches needed during Phase 02."
  - Locked product/delivery decisions confirmed by reality vs. revised in implementation.
  - The owner's "kept it running" judgment, with at least one concrete artifact (log excerpt, screenshot, written note) attaching evidence to the claim.
  - Phase 03 readiness — explicit statement that all four floor states were observed in the transition log and the empirical exit gate is satisfied.
- `notes/private/phase-02-swift-notes/INDEX.md` lands as a curated reading order across P2.03–P2.10's swift notes. Format: one bullet per ticket with a one-line "read this if you want to understand X" hook. Example:
  ```
  - [P2.03 — state-json-reader](P2.03-state-json-reader.md) — Codable + closed-enum decoding
  - [P2.05 — menubar-renderer](P2.05-menubar-renderer.md) — @MainActor and AppKit threading
  ```
- Doc-drift sweep — touch each of the following only when the implementation actually drifted from the plans:
  - `README.md` — only if user-visible behavior, commands, or project status changed.
  - `.son-of-anton/CLAUDE.md` — only if the orchestrator surface or rules changed (unlikely in Phase 02).
  - `docs/contracts/animation-state-vocabulary.md` — only if implementation surfaced an honest contract gap beyond the P2.02 forward-compat clause.
  - `docs/product/plans/phase-02-menu-bar-pet-foundations.md` — if and only if material divergence occurred; write `docs/product/plans/phase-02-as-shipped-ci-macos-tests.md` to capture the delta (mirroring Phase 01's `phase-01-as-shipped-delta.md` pattern). Skip if no material divergence.
  - `docs/template/overview/start-here.md` — only if delivered scope, commands, status, or deferrals changed.

## Red

- `Red: skip` — pure docs ticket; branch touches only `.md` files. Reviewer is the gate.

## Green

- Use the `soa-write-retrospective` skill to scaffold the retro doc; fill it in honestly. The skill owns section structure; this ticket owns the *content*.
- Curate the swift-notes INDEX by reading each `P2.NN-*.md` file in `notes/private/phase-02-swift-notes/` and writing the one-line hooks.
- Run the doc-drift sweep deliberately: open each candidate doc, check against current behavior, edit only if drift is real.
- If `phase-02-as-shipped-ci-macos-tests.md` is needed, write it; if not, explicitly state in the retro that no material divergence occurred.

## Refactor

- Run `bun run spellcheck` and add any new words to `cspell.json` as needed.
- Run `bun run format` (no-op for `.md` but standard pre-commit).

## Review Focus

- Retrospective is *honest* about surprises and shortfalls, especially around the soul-first exit gate ("kept it running"). If the owner abandoned the app for a day, the retro says so.
- Phase 01 patches subsection is complete: every standalone PR to `main` that fixed a hook/CLI/engine issue surfaced by Phase 02 use is listed.
- Swift-notes INDEX reads coherently as a Phase-02 learning path, not just a directory listing.
- Doc sweep didn't touch anything that didn't drift (no churn-for-churn's-sake edits).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a — docs-only ticket.
Why this path: retro structure is owned by `soa-write-retrospective`; this ticket owns content + the Phase-02-specific cross-link section + the swift-notes index.
Alternative considered: a separate ticket for each doc update. Rejected — Phase 01 already proved that a single closeout ticket prevents doc drift better than scattering edits across multiple late tickets.
Deferred: a phase-02 "what's next for Phase 03" outline. Phase 03 plan is its own `/soa plan` cycle, not retrofitted here.
Contract note: record here if any contract docs were touched beyond P2.02's forward-compat clause, and why.
