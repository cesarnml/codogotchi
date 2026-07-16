# P21.03 Fallback advances on ran-but-failed runners

Size: 2 points
Type: fix
Scope: subagent-review
Red: required

## Outcome

- `runSubagentWithFallback` (`tools/delivery/subagent-runner.ts`) advances to the next runner in `buildSubagentFallbackOrder` when an attempt returns `status: 'ran'` with `terminatedReason` in {`runner_failed`, `rate_limit`, `sandbox_denied`} — the issue #105 case where the CLI spawns and exits but the backing model produced no usable review.
- `advisory_violation` does **not** advance the chain: the runner reviewed but broke the no-writes contract; the violation records honestly (as today) and stops.
- `skipped` with `fallbackLevel: 'failed_all'` is recorded only when every runner in the chain fails to produce a usable review; every attempt remains auditable in `attemptedKinds` and the ledger.
- A successful fallback records `fallbackFrom` = the originally requested runner and `fallbackLevel: 'fallback'`, exactly as the existing unavailable/timeout path does.
- `docs/template/delivery/delivery-orchestrator.md`'s fallback description reflects the broadened trigger set.

## Red

- Write failing tests in `tools/delivery/test/subagent-runner.test.ts`:
  - requested `codex-cli` whose attempt returns `ran` + `runner_failed` advances to `claude-cli` (the issue's exact repro, in `PROGRAMMATIC_SUBAGENT_RUNNERS` order);
  - `ran` + `rate_limit` and `ran` + `sandbox_denied` also advance;
  - `ran` + `advisory_violation` does not advance and preserves the violation row;
  - all three runners failing → `skipped`, `fallbackLevel: 'failed_all'`, `fallbackFrom` preserved, `attemptedKinds` lists the full chain;
  - a genuinely completed `ran` result still returns immediately with no fallback.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P21.03): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Broaden the loop's advance condition (via `shouldFallbackToOtherRunner` or a sibling check for `ran` results) with the smallest change that passes; do not restructure the loop.

## Refactor

- If the advance predicate now has two homes (process-level and ran-level), unify into one clearly-named function; nothing else.

## Review Focus

- Interaction with P21.02: a `ran` + `completed_with_findings` result is a _successful_ review and must never trigger fallback.
- Ledger auditability: for a fallback that eventually succeeds, confirm the failed first attempt is still visible (attemptedKinds/rows) so post-hoc analysis can see the broken runner.
- Cost guard: the chain attempts each runner at most once — no retry-same-runner loops.
- Intentionally deferred: changing the fallback _order_ (stays `PROGRAMMATIC_SUBAGENT_RUNNERS` rotation); model-availability-aware fallback (out of scope per #78).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
