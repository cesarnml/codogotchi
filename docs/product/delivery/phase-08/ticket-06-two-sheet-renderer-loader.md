# P8.06 Maew two-sheet assets + 8-frame renderer loader

Size: 3 points
Type: feat
Scope: renderer
Red: required

> **Blocked until the two Maew sheets are committed** — `codogotchi-lite-spritesheet.webp` + `codogotchi-soa-spritesheet.webp`, generated per `notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md` (developer pre-delivery artifact). Do not ship Phase 07 placeholder rows as final.

## Outcome

- Maew's two real sheets are bundled (`apps/menubar/Fixtures/maew/`) with an updated `pet.json`, replacing the single placeholder `codogotchi-spritesheet.webp`.
- The renderer loads **both** sheets: `codogotchi-lite-spritesheet.webp` (11 rows / 8 frames) for the 9 hook/lite states + idle escalation, and `codogotchi-soa-spritesheet.webp` (10 rows / 8 frames) for the SoA gate states.
- Each ActivityState maps to (sheet, row); the renderer picks the SoA sheet for gate states and the lite sheet for hook states. The **Phase 07 temporary placeholder rows** (`green_tdd`→2, `red_tdd`→3, `open_pr`→4, `record_review`→8 on the single sheet) are removed.
- Animation plays **8 frames/row at 1.5s/loop, looping continuously** while the state is active (matches Codex cadence).
- Unknown/artless states still fall through to hook animation (Phase 07 contract preserved) — no gray pet, no crash.

## Red

- Test the ActivityState → (sheet, row) map: hook/lite states resolve to the lite sheet; the 10 gate states resolve to the SoA sheet; coverage is exact (every schema-v4 state maps, none to a placeholder row).
- Test the loader reads both sheets and computes 8 columns/row at the documented cell size; the 1.5s/8-frame timing is set.
- Test fall-through: an unknown gate name renders hook animation (no SoA row), preserving the Phase 07 resolver.
- Run the suite; confirm failure. Commit `[red]`.

## Green

- Add a multi-sheet loader (lite + soa) keyed by ActivityState; remove the placeholder-row mapping from P7.
- Wire the 8-frame / 1.5s timing into the pet scene(s) (`CodogotchiPet`/`MenubarRenderer`/`FloatingPetScene`).
- Bundle the two sheets + `pet.json`; seed into `~/.codogotchi/pets/maew/`.

## Refactor

- Consolidate sheet/row resolution into one table consumed by both menubar and floating renderers (avoid two divergent maps).

## Review Focus

- Exact 1:1 coverage of the schema-v4 closed enum across the two sheets — no state silently rendering a wrong/placeholder row.
- Idle escalation (`idle`/`idle_impatient`/`idle_frustrated`) selected by elapsed-idle thresholds from the **single** `idle` enum state — not new `state.json` values.
- Cell-size/column math against the real sheet dimensions (1536×2288 lite, 1536×2080 soa); reject if `width ÷ 8` isn't integral.
- That the Phase 07 placeholder rows are fully gone, not just shadowed.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: testGridColumnsIs8, testFrameIntervalIs1Point5Per8Frames, testLiteRowMapHasExactly9HookStates, testSoaRowMapHasExactly10GateStates — all failed immediately on the P7 single-sheet stubs.
Why this path: Phase 07 deferred the multi-sheet loader; this is the explicit follow-up that makes "SoA supported" real.
Alternative considered: keep one combined sheet — rejected; the tier model and premium 24-frame split need separate sheets.
Row order source: `notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md` — prompt order defines exact row indices for both sheets (11 rows lite, 10 rows SoA).
Resolution order change: CodogotchiPet is checked BEFORE CodexPet in both MenubarRenderer and FloatingPetScene. The lite sheet now self-contains all 9 hook states, making "Codex first" wrong for hook states. Codex remains the fallback for unknown/artless states (Phase 07 contract preserved).
GateJsonReader: switched from rowMap to soaRowMap for gate-renderability predicate. All 10 SoA gate states (including .advance and .pollReview, which were artless in P7) now have art.
Deferred: 24-frame premium pack (Phase 14); rpg sheet (tier 4); idle escalation thresholds (renderer selects idle-impatient row 1 / idle-frustrated row 2 after elapsed-idle timers, not implemented this phase).
