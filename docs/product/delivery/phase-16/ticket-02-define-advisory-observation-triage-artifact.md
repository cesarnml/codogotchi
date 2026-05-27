# P16.02 Define Advisory Observation Triage Artifact

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- SOA has a structured advisory-observation triage artifact format.
- The artifact records source report path, ticket id, observation text, disposition, rationale, and optional patch commit or follow-up reference.
- Valid dispositions are exactly `patched`, `rejected`, `deferred`, `already-covered`, and `converted-to-ticket`.
- Non-patched dispositions require a non-empty rationale.
- Malformed artifacts are rejected with clear validation errors.

## Red

- Add tests that fail until the artifact schema exists:
  - Round-trip a valid artifact with all five dispositions.
  - Reject an unknown disposition.
  - Reject a non-patched disposition without rationale.
  - Accept a patched disposition with a commit SHA.
  - Preserve source report and ticket identity.
- Commit with suffix `[red]`: `test(P16.02): define advisory observation triage artifact [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add artifact types, validation, read, and write helpers for advisory-observation triage.
- Store the schema in delivery tooling, not in the subagent runner ledger.
- Keep the artifact append/update semantics deterministic so re-running triage does not duplicate identical decisions.

## Refactor

- Share simple validation helpers with existing delivery artifact code only when it reduces real duplication.
- Keep the disposition artifact independent from external AI review triage artifacts.

## Review Focus

- Verify the artifact answers: what was observed, where did it come from, what did the primary decide, and why?
- Verify the schema does not imply advisory observations are blocking defects.
- Verify patched and non-patched disposition requirements match the product plan.

## Rationale

Red first: `bun test ./tools/delivery/test/p16-02.test.ts` failed because `../advisory-observation-triage` did not exist.
Why this path: added a dedicated delivery-tool artifact module with typed dispositions, strict validation, deterministic JSON read/write helpers, and stable merge semantics keyed by source report, ticket id, and observation text.
Alternative considered: extending the subagent-review ledger was rejected because Phase 16 explicitly keeps runner outcome and operator disposition as separate artifacts.
Deferred: the CLI command that discovers reports and writes this artifact remains in P16.03.
Contract note: ticket metadata was usable as written.
