# P21.05 Docs + retrospective + local dogfood DMG

Size: 1 point
Type: docs
Scope: menubar
Red: skip

## Outcome

- Phase delivery status / any developer-facing notes that still describe live shadow tooling, dual prompt-timer protocol pushes, fold-display prune titles, or throwaway prune allocators are updated to match the post-P21.01–04 codebase (only docs that would otherwise lie — no drive-by README rewrites).
- Retrospective written at `docs/product/retrospectives/phase-21-post-v3-cutover-cleanup-retrospective.md`, including: Phase 18 waived reverse-shadow soak; Phase 21 deleted the last shadow utilities without re-introducing a soak gate; freeze-adjacent surprises from P21.02–04; what was deferred and why.
- Local dogfood DMG packaged via the normal packaging script and installed as the daily driver.
- **No** public GitHub release and no download-page update for this phase.

## Red

- `Red: skip` — docs/retrospective + packaging; doc-only / process gate. Human review of the retrospective and packaging checklist is the gate. No automated test asserting doc wording.

## Green

- Write retrospective; update any lying developer docs discovered while closing the phase; package and install local DMG; record package/install evidence in Rationale (path + that it was installed as daily driver).

## Refactor

- None.

## Review Focus

- Retrospective must explicitly cover deleted-without-re-soak and the dual-era seams removed this phase.
- Confirm no public release was cut.
- Confirm product-plan exit conditions 1–6 are checked off against the landed stack.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
