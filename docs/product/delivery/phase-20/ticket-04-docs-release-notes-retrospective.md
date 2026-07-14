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

Red first: n/a (docs-only)
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
