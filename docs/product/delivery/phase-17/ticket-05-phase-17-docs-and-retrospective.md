# P17.05 Phase 17 docs + retrospective

Size: 2 points
Type: docs
Scope: codogotchi-gate
Red: skip

## Outcome

- `AGENTS.soa.md` documents the `gate.json` sidecar: `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`), single global file SoA owns, `{ gate, since, expires_at, plan_key, ticket_id }`, flat 3m TTL, best-effort, gated by `codogotchi.enabled`.
- The `.soa/events.ndjson` references in SoA docs are removed or marked retired (the writer is gone as of P17.04).
- The Phase 17 retrospective is written to `docs/product/retrospectives/phase-17-codogotchi-direct-gate-write-retrospective.md`.
- The product plan delivery-status line is updated to reflect completion.

## Red

- `Red: skip` — doc-only ticket (touches only `.md` files). No automated test; human review at the PR is the gate.

## Green

- Update `AGENTS.soa.md` (and any contract/troubleshooting note referencing `events.ndjson`) to describe the `gate.json` sidecar and the consumer boundary (codogotchi renderer reads it directly).
- Note the single-pet constraint (one global `gate.json`; concurrent multi-repo delivery shares it) and the no-explicit-clear behavior (renderer relies on `expires_at`).
- Write the retrospective using the `soa-write-retrospective` skill conventions: scope delivered, what held, what the flat 3m TTL surfaces, deferred `advance`/`red_tdd`-vs-anchor notes, follow-ups (TTL tuning, badge UI).

## Refactor

- Keep doc edits scoped to the gate-emission boundary; do not rewrite unrelated `AGENTS.soa.md` sections.

## Review Focus

- Docs match the shipped behavior (gate names, fields, TTL, path, config gate) — no drift from P17.01–P17.04.
- No lingering `events.ndjson` guidance that would mislead a consumer.
- Retrospective separates "code shipped" from "behavior observed" (live gate windows + hook bleed-through remain operator-validated until codogotchi Phase 07 renders `gate.json`).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (doc-only)
Why this path: AGENTS.soa.md update is a single section replacement — the old NDJSON guidance was fully retired and the new gate.json section covers all consumer-facing details. No broader doc rewrite was needed.
Alternative considered: Keeping the old NDJSON section as a "deprecated" note — rejected because the writer is gone, not just deprecated. A retired note would mislead a new consumer.
Deferred: Per-gate TTL documentation awaits codogotchi Phase 07 field data. Consumer repo migration guide is a follow-up note in the retrospective.
Contract note: No deviation from ticket metadata contract.
