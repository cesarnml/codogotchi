# P1.22 Retrospective + doc-drift sweep

Size: 2 points
Type: docs
Scope: docs

## Outcome

- `docs/product/retrospectives/phase-01-cli-convex-plumbing-retrospective.md` exists, authored via the `soa-write-retrospective` skill, covering:
  - What worked
  - What bit
  - What we'd change next time
  - Durable learnings for downstream phases (Phase 02 macOS app especially)
  - Each of the three plan-named risks revisited with actuals
  - The "owner-abandons-because-nothing-shareable" risk revisited honestly
- `README.md` rewritten to match the as-shipped product surface (commands, install, where data lives, what's deferred). No stale references to features that did not ship.
- `AGENTS.md` and `CLAUDE.md` reviewed for drift; any updates to commands, paths, or workflows captured.
- `docs/` swept for outdated runbooks, contracts, or links. Specifically: `docs/contracts/animation-state-vocabulary.md` reflects any P1.18 revisions; `docs/contracts/soa-event-feed.md` cross-references the SoA repo's mirrored doc.
- A short `docs/product/plans/phase-01-as-shipped-delta.md` (or similar) captures any divergence between the plan and what actually shipped, so Phase 02 planning can read the truth, not the intent.

## Red

- Skip Red — docs-only ticket.

## Green

- Run `soa-write-retrospective` skill against this phase's plan and delivery dir. Iterate on the draft with the developer.
- Diff README against current code surface: every command, flag, config field, file path mentioned should be verifiable. Update or remove drift.
- Sweep AGENTS.md / CLAUDE.md / `docs/` similarly.
- Write the as-shipped note if the plan-vs-shipped delta is material.

## Refactor

- N/A.

## Review Focus

- Retrospective is honest, not glossy. Specifically: did the seven-day validation work? Did the rate-limit cap bite? Did the PR-quality heuristic produce false positives? If yes, named in the retro.
- README accurately reflects the four CLI commands (`setup`, `sync`, `status`, `loot`) plus the two added (`config`, `vacation`). No phantom features.
- AGENTS.md / CLAUDE.md still describe an accurate workflow for the next phase's agent runs.
- All `docs/contracts/*` files reflect what shipped, not what was planned.
- If a contract was revised during P1.18 or P1.19, the revision is referenced from both the original contract doc and the retrospective.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.
