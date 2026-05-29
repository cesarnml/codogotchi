# P7.05 Phase 07 docs + retrospective

Size: 2 points
Type: docs
Scope: contracts
Red: skip

## Outcome

- A new `docs/contracts/gate-json.md` documents the `gate.json` sidecar contract: path (`$CODOGOTCHI_HOME/gate.json`), shape `{ gate, since, expires_at, plan_key, ticket_id }`, SoA-owned/renderer-read boundary, `expires_at` precedence, and the unknown/artless fall-through rule. Cross-references son-of-anton Phase 17 as the producer.
- `docs/contracts/soa-event-feed.md` is retired or marked superseded (the `.soa/events.ndjson` path is gone).
- `docs/contracts/animation-state-vocabulary.md` is updated to schema v4 (19-state enum), documents the 6-tier user model (Codex-only; Codex+lite; Codex+SoA; Codex+lite+SoA; Codex+lite+RPG; Codex+lite+SoA+RPG) with the "lite required for RPG, recommended for SoA" rule, and flags the temporary placeholder gate rows with their target soa-sheet destination.
- `README.md` reflects v4 / sidecar where user-visible (state names, no `work_mode`).
- The Phase 07 retrospective is written to `docs/product/retrospectives/phase-07-signal-honesty-and-soa-global-gates-retrospective.md`.

## Red

- `Red: skip` — doc-only ticket (touches only `.md` files). No automated test is required or expected; human review at the PR is the gate.

## Green

- Write `gate-json.md`; retire `soa-event-feed.md`; update `animation-state-vocabulary.md` to v4 + 6-tier model + temporary-placeholder note; touch `README.md` where user-visible behavior changed.
- Write the retrospective using `soa-write-retrospective` conventions: scope delivered, what held (atomic vocab, renderer-side merge), what the placeholder rows + flat-3m gate behavior surface, deferrals (`waiting_for_input`, multi-sheet loader, badge UI), and follow-ups (real soa-sheet art, TTL tuning, cross-process harness).

## Refactor

- Keep edits scoped to the sidecar/enum/tier boundary; do not rewrite unrelated vocabulary sections.

## Review Focus

- Docs match shipped behavior across P7.01–P7.04 (enum names, gate.json shape, precedence, removed `work_mode`/`gate_badge`).
- No lingering `events.ndjson` guidance that would mislead a consumer.
- 6-tier model and the "lite required for RPG / recommended for SoA" rule are stated; placeholder rows are clearly temporary.
- Retrospective separates "code shipped" from "behavior observed" (live gate windows + hook bleed-through remain operator-validated until real art + delivery data land).

## Rationale

Red first: n/a (doc-only ticket, Red: skip)

Why this path: Updated `animation-state-vocabulary.md` in place (avoided a full rewrite by targeting only the v4-relevant sections: title, activity states table, schema section, mapping table, spritesheet tables, reliability caveats). Added the 6-tier model as a new section. `soa-event-feed.md` marked superseded at the top with a pointer to `gate-json.md` — retained for historical reference per the spec ("retired or marked superseded").

Alternative considered: Full rewrite of `animation-state-vocabulary.md` — rejected because the forward-compat policy, HP overlay table, and manifest format are unchanged; targeted edits keep the doc smaller and easier to diff.

Deferred: RPG overlay docs — later phase. `waiting_for_input` wiring note included in the 6-tier table as "deferred."

Contract note: `xcodegen generate` is not run by `mac:test` — documented in retrospective as a follow-up item.
