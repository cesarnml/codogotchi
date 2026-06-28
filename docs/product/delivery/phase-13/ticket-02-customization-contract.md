# P13.02 Contracts: customization.json type + Zod schema

Size: 1 point
Type: feat
Scope: contracts
Red: required

## Outcome

- `packages/contracts/src/customization.ts` exports `customizationJsonSchema` and `CustomizationJson` type
- Schema fields: `schema_version` (literal 1), `platform_modes` (`Record<SourceEventOrigin, "own" | "combined" | "off">`), `idle_dismiss_ttl_seconds` (non-negative integer), `menubar_icon_monochrome` (boolean)
- Absent file or absent individual keys resolve to defaults: all origins `"own"`, TTL `300`, monochrome `false`
- Unknown `platform_modes` origin keys are tolerated (passthrough via `z.record`)
- Exported from `packages/contracts/src/index.ts`
- `bun run ci` passes

## Red

- Add `packages/contracts/src/customization.test.ts` asserting:
  - Valid full payload parses correctly
  - Absent `platform_modes` key resolves to empty map (defaults to "own" at read time)
  - Invalid mode string (e.g. `"hidden"`) fails validation
  - Unknown origin key (`"jetbrains"`) in `platform_modes` is tolerated
- Run `bun run ci` and confirm tests fail (file does not exist yet)
- Commit: `test(P13.02): customization.json schema validation [red]`

## Green

- Create `packages/contracts/src/customization.ts` with the Zod schema and TypeScript type
- Add export to `packages/contracts/src/index.ts`
- Make tests green

## Refactor

- No refactor needed — purely additive file

## Review Focus

- `platform_modes` should use `z.record(sourceEventOriginSchema, z.enum(["own", "combined", "off"]))` not a plain `z.record` — ensure origin keys are validated
- `idle_dismiss_ttl_seconds: 0` must be valid (represents "Never" dismiss)
- `schema_version` is a literal `1` — not the same constant as `STATE_JSON_SCHEMA_VERSION`; this is a separate config file with its own versioning

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: storing display prefs in `app-state.json` — rejected; `customization.json` is the coherent home for all user-facing display preferences written by both CLI and Swift.
Deferred: migration of existing per-platform settings from older config formats — no prior format exists.
Contract note:
