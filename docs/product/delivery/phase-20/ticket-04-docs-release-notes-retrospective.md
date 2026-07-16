# P20.04 Docs + release notes + retrospective

Size: 2 points
Type: docs
Scope: docs
Red: skip

## Outcome

- `docs/contracts/animation-state-vocabulary.md` (and any other slice-contract docs that still say schema v9 / omit stamps) describe schema **v10** and the four sticky fields, including set/clear semantics at product level.
- Release notes / dogfood install notes state that **app + hook install must refresh together**; no in-app outdated-hooks UX is introduced.
- Phase retrospective is written to `docs/product/retrospectives/phase-20-sticky-slice-timestamps-retrospective.md`.
- Product plan / delivery status lines reflect phase closeout readiness (no outstanding ticket Outcome gaps).

## Red

- Doc-only ticket: skip Red structurally. Human review at the PR is the gate.

## Green

- Update contract vocabulary and any hard-coded “schema_version 9” docs that would mislead implementers or dogfooders.
- Add lockstep release-note / install-refresh copy in the repo’s usual release or changelog surface for this ship.
- Write the required retrospective using the write-retrospective skill structure.

## Refactor

- None beyond doc placement consistency.

## Review Focus

- Docs must match shipped stamp semantics (especially: `turn_ended_at` on standby; errored freeze is app math from `errored_since`; Force Idle clears turn stamps).
- Do not add in-app upgrade UI under the guise of “docs.”
- Retrospective captures merge/clear surprises worth keeping for later clock fields.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (docs-only; Red structurally skipped per ticket policy, human review at the PR is the gate).
Why this path: updated the single existing contract doc (`docs/contracts/animation-state-vocabulary.md`) in place — bumped the title/current-shape section to v10, added a dedicated "Set/clear semantics (product level)" subsection enumerating the six lifecycle edges verbatim from the Grill-Me decisions (mid-turn preserve, prompt_submit/session_start refresh+clear, first-create session birth, first-errored set-once, standby+attention set-once, idle/Force Idle clear-but-preserve-birth), and explicitly called out that the menubar never writes `turn_ended_at` at the errored 60s threshold — matching P20.02's own Rationale and Review Focus. The prior v9-as-current shape section was demoted to a new "v9 slice shape (historical)" subsection rather than deleted, following the doc's own established pattern for every prior schema bump (v4–v9 all kept a historical note). Release notes went into README.md's existing "How it works" version-note paragraph sequence (the doc's established surface for `v2.0.0`/`v2.1.0`/`v2.2.0` notes) as a `v3_preview (Phase 20)` paragraph, stating the app+hook lockstep-refresh requirement and confirming no in-app outdated-hooks UX per the phase's explicit deferral.
Alternative considered: adding a new standalone `docs/contracts/prompt-timer-stamps.md` doc instead of extending the existing vocabulary doc — rejected because the ticket Outcome named `animation-state-vocabulary.md` specifically, the four stamps are slice-entry fields (not a separate contract), and every prior schema bump (v5 RPG fields, v6 `revive_until`, v7 slice directory, v8 RPG extraction, v9 hp removal) was documented in this same file rather than split out, so a new file would break the "one doc, one version history" convention future agents rely on.
Deferred: no new release-notes/changelog file was created — the ticket's Outcome says "the repo's usual release or changelog surface for this ship," and this repo's usual surface for dogfood-facing version notes is the README's version-numbered paragraphs (confirmed by reading v2.0.0/v2.1.0/v2.2.0 precedent), not a separate CHANGELOG.md (none exists in the repo). No in-app upgrade/mismatch UI was added or implied anywhere in this ticket's changes, consistent with the phase's explicit deferral.
Contract note: none — `Type: docs`, `Scope: docs`, and `Red: skip` all matched the ticket file as authored; no deviation.
