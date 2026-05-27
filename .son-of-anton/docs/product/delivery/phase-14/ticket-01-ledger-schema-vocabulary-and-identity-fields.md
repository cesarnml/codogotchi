# P14.01 Ledger schema vocabulary and identity fields

Size: 3 points
Type: feat
Scope: subagent-review
Red: required

## Outcome

- `SubagentRunnerOutcome` type expands from `clean | patched | skipped` to `clean | patched | deferred | skipped`. All four values are writable, readable, and pass the validator round-trip.
- New ledger row fields land: `schemaVersion: 1` (integer), `primaryAgent: string` (free-form, defaults to `"unknown"`), `runnerSelfReport: string | null` (the model's self-reported `runnerStatus` value when parseable; null otherwise), `fallbackFrom: SubagentRunnerKind | null` (the originally-requested subagent when fallback fired; null when no fallback).
- The validator parses Phase 14-shaped rows fully; rows missing the new fields are tolerated with sensible defaults (`schemaVersion: 0` or absent → permissive parse; `primaryAgent` absent → `"unknown"`; `runnerSelfReport` / `fallbackFrom` absent → `null`) so historical committed ledgers continue to be readable.
- A future schemaVersion bump does not crash existing readers — unknown versions parse permissively rather than throwing.
- **Green test target:** `bun test tools/delivery/test/subagent-runner.test.ts` covers all four outcome values writing/reading round-trip, all four new fields writing/reading round-trip, the permissive-parse path for schema-versionless rows, and the unknown-version-tolerated path.
- **Manual demo command:** `bun run tools/delivery/subagent-runner.ts --demo-fixture` (or equivalent ad-hoc script) writes a sample ledger with one row per outcome value (`clean`, `patched`, `deferred`, `skipped`), reads it back, and prints the parsed rows to stdout. Each row demonstrates all five new fields populated correctly.

## Red

- Add tests in `tools/delivery/test/subagent-runner.test.ts` that:
  - Construct a ledger row with `outcome: 'deferred'` and assert it round-trips through `coerceToValidLedgerRow` (or its Phase 14 successor) without loss.
  - Construct rows with each of `schemaVersion`, `primaryAgent`, `runnerSelfReport`, `fallbackFrom` populated and assert round-trip.
  - Construct a legacy-shaped row (no `schemaVersion`, no `primaryAgent`) and assert permissive parse returns sensible defaults.
  - Construct a row with `schemaVersion: 999` and assert it parses (permissive forward-compat) rather than throwing.
- Run `bun test` and confirm all new tests fail.
- Commit: `test(P14.01): ledger schema gains deferred outcome and identity fields [red]`

## Green

- Expand `SubagentRunnerOutcome` to include `'deferred'`.
- Expand `SubagentRunnerLedgerRow` (or equivalent type) with the four new fields.
- Update `coerceToValidLedgerRow` and the JSON validator to accept the new fields and tolerate missing-field cases per the permissive-parse semantics in the Outcome.
- Update the ledger writer to include the new fields when callers provide them; preserve omitted-field shape for backward compatibility with row constructors that don't yet populate them. (Callers updating to provide values lands in P14.02+.)
- Run `bun test`; confirm green.
- Commit: `feat(P14.01): expand ledger outcomes and add identity fields`

## Refactor

- Extract validator logic into a single `parseLedgerRow` function if the existing code duplicates parsing across writers and readers. Only refactor what you touched.
- If this ticket moves tracked files, bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` per the template instruction. (Expected: not needed for this ticket — pure type/validator changes inside `tools/delivery/`.)

## Review Focus

- Permissive-parse semantics: does the validator accept Phase 13-shaped rows (no `schemaVersion`, no `primaryAgent`) without throwing? Round-trip them through the new writer; do legacy consumers still parse the output?
- Default values: is `primaryAgent: "unknown"` applied when absent, or does the field remain `undefined`? The product-plan contract is `"unknown"` as an explicit string — verify the validator does not silently drop the field.
- Forward-compat: a row with `schemaVersion: 2` (hypothetical future bump) must parse without throwing. The current reader should treat unknown versions as "read what you can; don't enforce."
- What was intentionally deferred: callers (cli-runner.ts, subagent-runner.ts) are not updated to populate the new fields in this ticket — that lands in P14.02. This ticket only ships the schema, validator, and writer surface so P14.02 has a target to write to.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `expect(row.primaryAgent).toBe('unknown')` on a legacy-shaped row — validator did not project that default.
Why this path: The Outcome contract reads "primaryAgent absent → 'unknown'" but materializing that into the validator output broke nine existing P10/P11/P13 `toEqual(artifact)` tests by adding fields not present on the input artifact. We split the contract: the validator preserves input shape exactly (no back-fill), and reader-side helpers (`getPrimaryAgent`, `getRunnerSelfReport`, `getFallbackFrom`) materialize the documented defaults. Same semantics, no churn on legacy assertions. `schemaVersion` absence is also preserved so legacy rows remain byte-distinguishable from Phase-14 rows.
Alternative considered: Back-fill defaults inside `validateRunnerArtifact` and update each `toEqual(artifact)` legacy test to include the new fields. Rejected: widens the diff across prior phases' tests without any change in stored ledger shape and risks masking real divergence when later phases assert exact artifact shapes.
Deferred: Caller migration of `cli-runner.ts` / `subagent-runner.ts` to populate the new fields lands in P14.02+. This ticket only ships the schema, validator, writer surface, and reader helpers so P14.02 has a target.
Contract note: none — "tolerated with sensible defaults" is honored via reader helpers rather than parse-time back-fill, which keeps the writer surface monotonic.
