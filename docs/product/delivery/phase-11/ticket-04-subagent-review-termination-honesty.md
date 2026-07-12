# P11.04 subagent-review termination honesty

Size: 3 points
Type: fix
Scope: delivery

## Outcome

- The `subagent-review` CLI waits for the runner subprocess to exit before sampling `git status --porcelain` for outcome detection. The orphan-edit race window (runner writes after porcelain reads clean) is closed.
- The CLI refuses to record `outcome: 'clean'` when the runner's reported `terminatedReason` is not `'completed'`. Non-completed terminations record their actual `terminatedReason` and an outcome that reflects the incomplete state (not `clean`).
- The same-command auto-fallback (preferred runner → other runner) fires only for hard binary-availability failures (`unavailable` from `tryRunner` — preferred binary not on PATH) and timeouts. It does **not** fire for ambiguous runner output such as rate-limit body text in stdout, sandbox-denial-as-result, or exit-code-0-with-no-work. Those exit honestly via `terminatedReason` and let the primary-agent loop decide whether to retry.
- `bun run ci` is green.

## Red

- Add a test that simulates a runner subprocess writing files _after_ the CLI's old porcelain sample point. Assert the recorded outcome reflects the post-exit porcelain state (i.e., `patched` if files were written, not `clean`).
- Add a test that constructs a runner result with `terminatedReason: 'rate_limit'` and confirms the CLI refuses to write `outcome: 'clean'`.
- Add a test that simulates ambiguous runner output (e.g., a rate-limit signature in stdout with exit code 0) and confirms the CLI does **not** auto-fall-back to the other runner — it records `terminatedReason` honestly and exits.
- Add a test that simulates the preferred runner binary missing from PATH (`unavailable`) and confirms auto-fallback **does** fire.
- Run the suite and confirm all four fail.
- Commit with suffix `[red]`: `test(P11.04): termination honesty for subagent-review [red]`

## Green

- In the CLI runner code path, move the porcelain sample to after `await child.exited` (or equivalent subprocess wait).
- Add a guard at outcome-recording time: if `terminatedReason !== 'completed'`, override an incoming `clean` outcome to a non-clean honest value (the product plan does not name one — use `'incomplete'` or carry through the `terminatedReason` as the outcome surrogate; decide at implementation and document in Rationale).
- Narrow the auto-fallback predicate to `unavailable | timeout` only. Remove fallback triggers for ambiguous-runner-output cases. Surface those as `terminatedReason: 'rate_limit' | 'sandbox_denied' | 'runner_unavailable'` per the schema landed in P11.01.

## Refactor

- The outcome-detection function may have accumulated branches across phases. Consolidate the post-exit ordering into one clear sequence — but only within the function this ticket touches.

## Review Focus

- Subprocess-wait correctness: confirm `await child.exited` or the chosen primitive handles abnormal exits (signal kill, parent timeout) without leaking the porcelain-read past a hung child.
- The fallback predicate's new shape — confirm it is documented inline (a short comment naming the two allowed triggers and why ambiguous-output cases are excluded) since this is the rare case where a code comment captures non-obvious _why_.
- Choice of outcome value when `terminatedReason !== 'completed'` and operator did not supply one. Whatever the chosen sentinel, confirm downstream artifact consumers handle it without assuming `clean | patched` exhaustiveness.
- Whether `--force` from P11.03 interacts with these guards. Default: it should not — `--force` overrides idempotency, not honesty.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: the four invariants in `tools/delivery/test/p11-04.test.ts` — porcelain ordering, terminatedReason-blocks-clean, ambiguous-output-no-fallback, unavailable-does-fallback. They failed at the suite level because the helper functions (`decideSubagentOutcomeFromRunner`, `shouldFallbackToOtherRunner`) and the extended `SpawnResult` / `RunnerAttemptResult` carrying `terminatedReason` did not exist yet.

Why this path: the smallest acceptable change extended `SpawnResult` with an optional `terminatedReason`, lifted it onto the `ran` variant of `RunnerAttemptResult`, and split the two policy decisions (honesty guard, fallback predicate) into pure helpers consumed by the CLI loop. The CLI now (a) detects rate-limit / sandbox-denied signatures in stdout/stderr at the spawn closure, (b) carries that reason through `tryRunner`, (c) overrides `outcome: 'clean'` to `'skipped'` when termination was not `completed`, and (d) only falls back on `unavailable | timeout`. `spawnSync` is already synchronous, so the porcelain sample is post-exit by construction; the test pins that contract.

Sentinel choice for non-completed terminations: override `clean` → `'skipped'` (already in the `SubagentRunnerOutcome` union) and carry the honest `terminatedReason` on the invocation record. This avoids inventing a fourth outcome value, keeps downstream consumers exhaustive over `clean | patched | skipped`, and still distinguishes the failure mode through `terminatedReason`. `patched` is preserved when termination was not completed because the runner's writes are already on disk.

Alternative considered: introducing a fourth outcome literal `'incomplete'`. Rejected because every artifact validator and policy site already pattern-matches `clean | patched | skipped`, and `'skipped'` + a non-completed `terminatedReason` already encode "the runner did not review the diff" honestly.

Deferred: deeper rate-limit / sandbox-denial detection (e.g., structured error envelopes from the runner binaries) is out of scope. The substring detection runs at the spawn closure and is intentionally lightweight; richer detection can be added without changing the helper contract.

`--force` interaction (Review Focus item): `--force` from P11.03 controls idempotency inside `decideSubagentReviewMode`. It does not touch the termination-honesty guard or the fallback predicate, so it cannot be used to record a dishonest `clean` from a non-completed runner.

Contract note: no deviation from `Type: fix` / `Scope: delivery`.
