# P14.01 Contracts: assignments.json schema + minimalist customization mode

Size: 2 points
Type: feat
Scope: contracts
Red: required

## Outcome

- `@codogotchi/contracts` exports `assignmentsJsonSchema` (Zod) and `AssignmentsJson` type: `schema_version: 1`, a mandatory `default: string` (non-empty petId), and optional `claude_code`/`vscode`/`codex`/`cursor`/`antigravity` petId overrides.
- The schema rejects a payload missing `default` and tolerates absent platform keys (partial overrides).
- `customizationJsonSchema.platform_modes` accepts `"minimalist"` as a fourth value alongside `"own"`/`"combined"`/`"off"`.
- `index.ts` re-exports the new assignments module.

## Red

- Add `packages/contracts/src/assignments.ts` test asserting: a full 6-key payload parses; a payload with only `default` parses (platform keys optional); a payload missing `default` fails; an empty-string `default` fails.
- Extend `customization.test.ts` to assert `platform_modes: { claude_code: "minimalist" }` parses and round-trips as `"minimalist"`.
- Run `bun run test` (contracts) and confirm the new assertions fail.
- Commit with suffix `[red]`: `test(contracts): assignments schema + minimalist mode [red]`.
- Do not write any implementation until this commit exists on the branch.

## Green

- Add `packages/contracts/src/assignments.ts` with `assignmentsJsonSchema` and `AssignmentsJson`. Use `z.string().min(1)` for petIds; mirror the `customization.ts` pattern for defaults.
- Add `"minimalist"` to the `z.enum` in `customizationJsonSchema.platform_modes`.
- Re-export from `index.ts`.

## Refactor

- Keep the assignments module shaped like `customization.ts` (single schema + inferred type export). No opportunistic changes to other contracts.

## Review Focus

- `default` must be required while the 5 platform keys are optional — verify the Zod shape encodes exactly that (not all-optional, not all-required).
- Confirm adding `"minimalist"` to the enum does not change the `.default({})` behavior or break existing `platform_modes` round-trip tests.
- Note: this ticket only defines the contract; the Swift reader (P14.03) and migration are separate. No `schema_version` bump on `customization.json` (enum extension is additive).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
