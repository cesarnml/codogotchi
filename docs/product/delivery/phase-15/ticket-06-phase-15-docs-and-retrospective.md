# P15.06 Phase 15 docs + retrospective

Size: 1 point
Type: docs
Red: skip

## Outcome

- `AGENTS.soa.md` documents `.soa/` as a codogotchi local-only sidecar directory, references the `codogotchi.enabled` config field, and points to the codogotchi contract doc (`docs/contracts/soa-event-feed.md` in the codogotchi repo) for the file schema.
- The gitignore example in `AGENTS.soa.md` includes a `.soa/` entry with a one-line comment explaining its purpose.
- The product plan, implementation plan, and final ticket cross-link the codogotchi alignment draft at `notes/public/codogotchi-alignment-draft.md` (already committed in the plan PR).
- A retrospective document is written at `docs/product/retrospectives/phase-15-codogotchi-gate-event-emission-retrospective.md` covering: what the emit pattern proved out, the config gate's reception, the four deferred events and what each will need, and any drift from the original product plan.
- `README.md` and `docs/template/overview/start-here.md` are checked for user-visible references that need updating (per the repo's Ticket Completion Checklist).

## Red

- Doc-only ticket — `Red: skip` per the canonical template. Branch touches only `.md` and JSON files; no automated test is required.
- Use the `soa-write-retrospective` skill at `.agents/skills/write-retrospective/SKILL.md` for the retrospective section structure.

## Green

- Edit `AGENTS.soa.md`: add a `.soa/` sidecar paragraph, gitignore example update, and a one-line reference to `notes/public/codogotchi-alignment-draft.md`.
- Verify `notes/public/codogotchi-alignment-draft.md` is committed (it was written during the plan PR; this ticket only verifies presence and updates any stale cross-links).
- Write `docs/product/retrospectives/phase-15-codogotchi-gate-event-emission-retrospective.md` using the `soa-write-retrospective` skill.
- Append a "PR link" line to the product plan TL;DR pointing at the final phase PR set once the closeout-stack is identified.
- Audit `README.md` and `docs/template/overview/start-here.md` for any user-visible behavior change references that need updating — likely just a mention of the new `.soa/` sidecar in user-facing setup docs if it appears there.

## Refactor

- No code changes. Doc-only ticket.

## Review Focus

- `AGENTS.soa.md` accurately describes when `.soa/` appears (any consumer repo with `codogotchi.enabled` running SoA delivery commands) and what it costs (nothing — local-only, gitignore-able).
- The retrospective captures what was learned during P15.01–P15.05, especially any surprises in the emit-point integration tests or the config-gate semantics.
- All cross-links between docs (product plan → implementation plan → retrospective → codogotchi draft) resolve cleanly.
- `.soa/` listed in any documented gitignore example.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
