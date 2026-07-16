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

Red first: `Red: skip` — docs/retrospective + packaging; human review of the
retrospective and packaging checklist is the gate.

Why this path: Scrubbed three Sources doc-comments that still named the deleted
class `SessionNumberAllocator` (`PlatformSessionBadge`, `MenubarMenu`,
`CustomizationJsonReader` default-cap docs) to `SessionNumberAllocatorState`.
Updated the product-plan delivery status + problem framing to past tense so it
no longer claims the leftovers still ship. Wrote
`docs/product/retrospectives/phase-21-post-v3-cutover-cleanup-retrospective.md`
covering Phase 18 waived soak → Phase 21 delete-without-re-soak, freeze-adjacent
surprises from P21.02–04, and explicit deferrals. Packaged via
`bash scripts/package-dmg.sh` → `builds/Codogotchi.dmg` (62M, version 2.7.0
build 12); quit running app; mounted volume; replaced
`/Applications/Codogotchi.app`; `xattr -cr`; relaunched. Confirmed
`pgrep -fl Codogotchi` → `/Applications/Codogotchi.app/Contents/MacOS/Codogotchi`.
No `gh release create`; latest public release remains the pre-existing `v2.7.0`.

Alternative considered: drive-by README rewrite of historical phase retros —
rejected; ticket scope is lying *present-tense* developer notes only.

Deferred: flat-gate fallback; Own/Minimalist extract; waived P18 soak gaps;
public notarized ship (Track 2).

Contract note: comment-only Sources edits + docs; no intentional UX change.
Dogfood DMG is local-install only.

Exit conditions 1–6 (product plan) checked against landed stack:

1. Shadow trio gone — P21.01 greps + deleted harness tests.
2. Husk absent / lie-scrub — P21.01 (husk already gone on base); remaining
   allocator-class comment refs scrubbed here.
3. Bare prune title / fold-display gone — P21.02.
4. Presentation-only production timer push — P21.03.
5. Disk-only Pruner / class allocator deleted — P21.04.
6. Suite green under prior tickets; local DMG installed as daily driver;
   retrospective filed — this ticket.
