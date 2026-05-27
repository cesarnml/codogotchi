# P2.02 Contract doc — animation-state-vocabulary forward-compat clause

Size: 1 point
Type: docs
Scope: contracts
Red: skip

## Outcome

- `docs/contracts/animation-state-vocabulary.md` gains an explicit **Forward-compatibility policy** subsection under the existing **Revision policy** section, stating:
  - Renderers MUST accept `schema_version <= EXPECTED_VERSION` (parse best-effort, ignore unknown fields).
  - Renderers MUST refuse `schema_version > EXPECTED_VERSION` (treat as a hard failure, surface as a desaturated visual or equivalent error mode).
  - Adding new optional fields does not require a schema bump; changing the meaning of existing fields does.
- The subsection documents the rationale: older hooks should keep working when the renderer ships a newer expected version; newer hooks force a renderer update (the renderer is the lagging consumer).
- A "Renderer tooltip copy" subsection (or appendix) records the two canonical tooltip strings Phase 02 will use, so the contract doc is the source of truth for the wording:
  - Missing or non-integer `schema_version`: `"state.json schema_version is missing — codogotchi-hook may be too old."`
  - Newer-than-expected: `"state.json schema_version is v{got}; this app supports v{expected}. Update the menu bar app."`
- The doc still names `schema_version: 1` as the current contract version; this ticket does not bump it.
- No code changes. The Swift `StateJsonReader` in P2.03 will consume this clause; landing the contract doc first preserves Phase 01's discipline (contract before consumers).

## Red

- `Red: skip` — doc-only ticket; the branch touches only `.md` files. No automated test required or expected. Reviewer is the gate.

## Green

- Edit `docs/contracts/animation-state-vocabulary.md` in place. Insert the forward-compat clause and the tooltip-copy appendix.
- Run `bun run spellcheck` and add any new words (e.g., none expected; "tooltip" and "renderer" are standard) to `cspell.json` if needed.
- Run `bun run format` (biome will no-op on `.md` but is part of the standard pre-commit pass).

## Refactor

- Skim the doc once end-to-end after the edit to confirm the new subsection reads coherently against the existing Revision policy section.

## Review Focus

- Is the policy stated unambiguously enough that an agent implementing P2.03 cannot reasonably misread it?
- Do the tooltip strings match what P2.07's failure visuals will display, character-for-character?
- Is the rationale captured (older hook = OK, newer hook = block) so future contract revisions know which direction the asymmetry runs?

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a — doc-only.
Why this path: contract-before-consumer matches Phase 01's P1.02 discipline. Landing the forward-compat clause as its own one-point ticket means P2.03's StateJsonReader has a single unambiguous reference to implement against.
Alternative considered: strict equality (any deviation is a failure visual). Rejected because every future schema bump would require a coordinated app+hook release; older hook on newer app should keep working.
Deferred: backward-compat policy for renderer-driven schema rollbacks (out of scope; not a real failure mode).
Contract note: none.
