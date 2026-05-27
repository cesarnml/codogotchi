# P3.07 Validation runbook + rare-state synthetic-event recipes

Size: 1 point
Type: docs
Scope: docs
Red: skip

## Outcome

- A new runbook at `docs/runbooks/phase-03-validation.md` documents the synthetic-event recipes needed to verify the four rare SoA-driven states that cannot be reliably observed during a normal working day: `nervous`, `ascended`, `calling_for_backup`, `panicking`.
- Each recipe contains:
  - The exact NDJSON line to append to `.soa/events.ndjson` (with realistic `ts`, `plan_key`, `ticket_id`).
  - The expected `activity_state` the hook should classify after seeing the line.
  - The expected sprite row that should paint in the menubar (cross-referenced to the codogotchi sheet's row table in the contract).
  - The expected transition log entry that should land in `~/.codogotchi/state-transitions.log`.
- A "post-validation cleanup" section describes how to remove or roll the synthetic NDJSON lines so the runbook's evidence doesn't pollute future SoA delivery runs.
- A "what counts as evidence" section explicitly documents what to capture for the Phase 03 exit condition #3: timestamp, observed state in the log, photo or screenshot of the menubar painting the right sprite. (No tooling — owner's judgment + log excerpts.)
- The runbook also documents the recipe for verifying exit condition #4 (real hook detection of `requesting_input` and `errored`): how to deliberately trigger a Claude/Codex Stop-with-input-awaited event, and how to deliberately trigger an agent response failure (e.g., kill the network at the right moment, or use a known rate-limited request).

## Red

Doc-only ticket. `Red: skip` per the canonical template's doc-only rule: tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal.

## Green

- Write `docs/runbooks/phase-03-validation.md` from scratch. Reference structure: `docs/runbooks/phase-01-validation.md` (Phase 01's existing runbook) for tone and section layout, but do not copy structure verbatim — Phase 03's validation surface is different (rare-state synthetic events, not pipeline component verification).
- Cross-reference the contract (`docs/contracts/animation-state-vocabulary.md`'s Codogotchi Sheet row table) for sprite-row expectations rather than restating them.
- Include working NDJSON examples. Verify each example parses as a valid `SoaEventLine` per the contract before committing.

## Refactor

- Confirm cross-references to the contract, the codogotchi sheet, and the Phase 01 runbook all resolve to valid paths.
- The runbook should be useful as a *one-pager during the validation step*, not a treatise. If the runbook exceeds ~3 screens, trim — the operator running validation is the owner, and the owner already knows the system.

## Review Focus

- The four NDJSON recipes are syntactically correct and the `name` field for each matches the contract's SoA event vocabulary exactly: `risky_diff_detected`, `stage_advanced`, `subagent_invoked`, `verification_failed`.
- Each rare-state recipe identifies the codogotchi sheet row that should paint — owner can spot a mis-mapping by reading the runbook before P3.08 closes the phase.
- "Post-validation cleanup" is concrete: command, expected file state. No "remember to clean up" admonitions without a recipe.
- The `requesting_input` / `errored` real-detection recipes are honest about how to trigger each — including which trigger mechanism is reliable and which is finicky.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first — N/A for doc-only]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
