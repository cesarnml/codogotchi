# P1.02 IPC contract — animation state vocabulary

Size: 2 points
Type: docs
Scope: contracts

## Outcome

- `docs/contracts/animation-state-vocabulary.md` exists and defines: the closed enum of activity states, the closed enum of HP overlay states, the `state.json` v1 schema (including a `schema_version` field), and the mapping table from raw signal classes to animation states.
- `packages/contracts/src/animation-state.ts` exports matching TypeScript types and zod schemas. Types are exhaustive (closed enums via `as const` union, not loose `string`).
- `packages/contracts/src/state-json.ts` exports the `state.json` v1 schema and a zod parser.
- The doc declares which states are reliable (sourced from explicit events) versus heuristic (inferred from tool-call patterns).
- Nothing consumes these types yet — they sit ready for P1.06 (Convex schema's `mood` field), P1.18 (hook binary), P1.19 (SoA mapping).
- Ticket carries an explicit allowed-revision flag: P1.18 may revise once, with the revision logged in P1.18's Rationale and the doc updated accordingly.

## Red

- **Skip Red.** Doc-only and types-only ticket. The doc is reviewed by a human at the PR; the types are validated by downstream tickets when they consume them. Asserting exact doc wording in a test couples CI to legitimate doc revision.

## Green

- Draft `docs/contracts/animation-state-vocabulary.md` with sections: Overview, Activity States (closed enum + meaning + source signal + reliability), HP Overlay States (`thriving`, `getting_sick`, `near_death`, `ghost` + HP bucket boundaries), `state.json` v1 schema, Mapping Table, Reliability Caveats, Revision Policy.
- Capture activity states the plan calls out: `implementing`, `running-tests`, `reviewing`, `pushing`, plus SoA-derived `hyped`, `focused`, `nervous`, `waiting`, `celebrating`, `ascended`, `calling_for_backup`, `panicking`, plus a baseline `idle`. Document the source signal class and reliability tag for each.
- Implement zod schemas in `packages/contracts/src/animation-state.ts` and `packages/contracts/src/state-json.ts`. Export types via `z.infer<>`. Add a re-export in `packages/contracts/src/index.ts`.
- Add a brief `packages/contracts/README.md` pointing at the doc.

## Refactor

- None — first commit of these artifacts.

## Review Focus

- Closed enum exhaustiveness: every state mentioned in the doc has a matching zod literal and vice versa. Reviewer should grep one side against the other.
- `schema_version` field present and starts at `1`. Reviewer confirms future revisions bump this rather than silently mutating shape.
- Reliability tags honest: do not mark heuristic states (`reviewing` from "many sequential Reads") as reliable. Read the plan's caveat that these are best-effort.
- HP bucket boundaries match what the Health engine will compute in P1.04.
- `packages/contracts/` exports are tree-shakable (named exports, no default).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.
