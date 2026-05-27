# P3.01 Schema v2 — contract doc + TS contracts package

Size: 2 points
Type: feat
Scope: contracts
Red: required

## Outcome

- `docs/contracts/animation-state-vocabulary.md` includes a `state.json` v2 example with `schema_version: 2` and at least one v2 state demonstrated (e.g., `requesting_input` or `errored`).
- The revision policy section of the contract doc records that Phase 03 is the formal v2 bump per the policy's "After P1.18 lands, further changes require a new ticket and a separate schema-version bump" clause.
- `packages/contracts/src/animation-state.ts` has `requesting_input` and `errored` appended to `ACTIVITY_STATES` (closed enum preserved; no string escape hatch).
- `packages/contracts/src/state-json.ts` exports `STATE_JSON_SCHEMA_VERSION = 2`.
- The zod schema for `state.json` parses a v2 payload (with one of the new states) successfully.
- All prior v1 payloads still parse — backward compatibility preserved by the forward-compat policy (`got ≤ expected`).
- A payload with `schema_version: 3` (one ahead of the new `EXPECTED_VERSION`) is rejected at the parser layer.

## Red

- Write a test that asserts `STATE_JSON_SCHEMA_VERSION === 2` after the change.
- Write a test that a v2 payload with `activity_state: "requesting_input"` parses successfully.
- Write a test that a v2 payload with `activity_state: "errored"` parses successfully.
- Write a test that a previously-valid v1 payload still parses.
- Write a test that a `schema_version: 3` payload is rejected.
- Run `bun run test` against the contracts package and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P3.01): schema v2 enum + version + parser [red]`.
- Do not write any implementation until this commit exists on the branch.

## Green

- Bump `STATE_JSON_SCHEMA_VERSION` from `1` to `2` in `packages/contracts/src/state-json.ts`.
- Add `"requesting_input"` and `"errored"` to the `ACTIVITY_STATES` literal tuple in `packages/contracts/src/animation-state.ts`.
- Update the v1 example block in `docs/contracts/animation-state-vocabulary.md` to a v2 example (`schema_version: 2`, one of the new states as `activity_state`). The v1 example can be removed or kept as a "historical / still-valid v1" reference; pick the cleaner option in implementation.
- Update the revision policy section to record the v2 bump as planned by Phase 03 (one line; do not rewrite the policy).
- Smallest change that makes the failing tests pass — no opportunistic refactoring of the contracts package.

## Refactor

- Keep the contracts package change tight. The v2 additions are appended to existing tuples — do not reorder existing entries.
- Confirm the zod schema still surfaces useful error messages for the v3-rejection path; if the error message degrades, restore it.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`. (Not expected for this ticket — no file moves.)

## Review Focus

- Closed-enum discipline is preserved (no `string` escape hatch in the zod schema or TS type).
- The forward-compat policy is honored exactly as documented in the contract (`got ≤ expected` accepted, `got > expected` refused).
- The state.json v2 example in the doc matches the actual zod-validated shape — no drift between contract and code.
- The revision-policy update is a one-line record, not a policy rewrite.
- Tests cover the four meaningful cases: v2-with-new-state OK, v1 OK, v3 refused, enum exhaustiveness.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `STATE_JSON_SCHEMA_VERSION === 2` and the two parses-with-new-state cases — the v1-still-parses and v3-rejected cases passed pre-implementation, but were kept as regression guards for the forward-compat policy (`got ≤ expected`).
Why this path: smallest change — append `"requesting_input"` and `"errored"` to `ACTIVITY_STATES`, raise `STATE_JSON_SCHEMA_VERSION` to `2`, and swap `z.literal(STATE_JSON_SCHEMA_VERSION)` for `z.number().int().min(1).max(STATE_JSON_SCHEMA_VERSION)` so prior v1 payloads keep parsing while v3 is refused. No reorder, no new types.
Alternative considered: leaving `z.literal(STATE_JSON_SCHEMA_VERSION)` would have refused v1 payloads under the new constant, violating the forward-compat policy's "`got ≤ expected` accepted" clause. Rejected.
Deferred: hook-side detection of `requesting_input` and `errored` (P3.02); Swift renderer enum expansion + sheet remap (P3.03/P3.04); `EXPECTED_VERSION` bump on the Swift side (P3.04). The contracts package change here is contract-only.
Contract note: ticket metadata is compliant — `Type: feat`, `Scope: contracts`, `Red: required`.

### Cross-ticket pre-flight

Two structural fixes were needed before the orchestrator's pre-PR gates worked for a TS-only ticket. Both are bottom-of-stack tooling rather than P3.01 contract scope, but they are required for every downstream Phase 03 ticket too. Their locations:

- On `main` (commit `ffe9caa chore(p3): pre-flight fixes for phase-03 ci baseline`): `biome.json` rewrite for Biome 2.x, `MaliPetTests` stale-scale assertion repair, and `## Stage Gates` reorder so the plan parses for `bun run deliver`.
- On this branch ahead of the `[red]` commit (`2c8b90f chore(p3): include bun tests in the ci gate`): root `ci`/`ci:quiet` chained only `biome check` + `xcodebuild test`, so `bun run deliver post-red` (which runs `bun run ci`) could not see failing TypeScript tests. Added `bun test packages convex` between verify and mac:test; scope is explicit so the upstream Son-of-Anton subtree's self-tests do not run in the consumer repo.

### Subagent review patch (post-review)

Codex-cli (advisory subagent) flagged one actionable correctness gap: `RELIABLE_ACTIVITY_STATES` in `packages/contracts/src/animation-state.ts` did not include `requesting_input` or `errored`, even though the contract doc classifies both as `reliable`. Patched in `[subagent-review]` commit: appended both to the tuple. Same commit also fixed two human-review doc-drift items the subagent surfaced: (1) the contract doc's intro line still said "the v1 `state.json` schema" — corrected to v2; (2) this Rationale's pre-flight section claimed both structural fixes were on this branch — corrected to note one is already on `main` and one is on this branch.

While running the post-patch `bun run ci:quiet`, two `hook-binary.test.ts > runHook` cases (`writes state.json on first event…` and `classifies SoA gate event as celebrating`) failed because `runHook` resolves its SoA root via `process.cwd()` when `CLAUDE_PROJECT_DIR` / `CODEX_PROJECT_DIR` are absent. Inside a delivery-orchestrator worktree, the real `.soa/events.ndjson` contains `subagent_invoked` events, which the hook then surfaces as `calling_for_backup` and overrides the test's injected state. Folded a one-place fix into the same `[subagent-review]` commit: the `runHook` describe block now redirects `CLAUDE_PROJECT_DIR` to the fresh per-test tmpdir in `beforeEach` and restores the prior value in `afterEach`. Test isolation is the right shape; without it, this test suite is environment-flaky and would have shown up later when more SoA gate events accumulated.
