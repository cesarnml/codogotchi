# P14.02 Runner selection, naming, and classification fidelity

Size: 5 points
Type: feat
Scope: subagent-review
Red: required

## Outcome

- The `codex-exec` runnerKind value is renamed to `codex-cli` across the codebase: `SubagentRunnerKind` union, runner module guards, `VALID_RUNNER_KINDS` array, soa-sync.sh prose, CLI flag values, help text, agent-facing skill prose, all docs. `claude-cli` retains its name. No dual-name fallback.
- `/soa execute` and `/soa resume` accept `--subagent <claude-cli|codex-cli>` as a strict enum. A project-level default field `subagentRunner: "claude-cli" | "codex-cli"` lives in `orchestrator.config.json`. Precedence: `--subagent` flag > config field > hard error with a message naming both resolutions and pointing at cross-family best-practice docs. The previous `--preferred-runner` flag is removed.
- An optional `--primary <kind>` flag and `orchestrator.config.json:primaryAgent` field accept free-form string values (`claude`, `codex`, `cursor`, `composer`, `copilot`, `aider`, etc.). Defaults to `"unknown"` if neither flag nor config provides a value. The flag is information-only and does not drive orchestrator behavior. Each subagent-review invocation records the value as a singular `primaryAgent` field on its ledger row.
- The codex-cli runner step trusts the model's self-reported `runnerStatus` trailer when present and parseable. The ledger row records `runnerSelfReport: <value>` from the trailer; if the external classification disagrees, both are recorded so the disagreement is auditable.
- "Authentic rate-limit signal" per runner is defined in the runner's config (not inferred from stderr text). Codex-cli's authentic signal is parsed from its known exit code and structured error response; claude-cli's authentic signal is parsed analogously. Stderr noise that resembles rate-limit language but lacks the authentic signal is classified as "completed with noise," not "rate-limit."
- A runner is **unavailable** when any of the following holds: binary missing, invocation errors before producing output, runner returns an authentic rate-limit signal, network failure during invocation, or the runner fails to process the prompt (parse error, timeout, contract violation). Any unavailability triggers fallback to the other configured runner. The ledger row records `outcome: skipped` only when every configured runner is genuinely unavailable.
- When the operator-specified subagent fails availability and fallback fires, the ledger row records `runnerKind` (what actually ran) plus `fallbackFrom: <originally-requested>` (what the operator asked for). Same-family-by-fallback is therefore distinguishable from same-family-by-choice in the ledger.
- **Green test target:** `bun test tools/delivery/test/subagent-runner.test.ts` (extended) and `bun test tools/delivery/test/cli-runner.test.ts` cover: codex-cli classification trusts model self-report; rate-limit-shaped stderr without authentic signal does not produce `skipped`; missing `--subagent` and missing config field together produce hard error; `--subagent codex-cli` runs codex-cli; `--subagent codex-cli` with codex-cli unavailable falls back to claude-cli and records `fallbackFrom: codex-cli`; both runners unavailable produces `skipped` honestly; `--primary cursor` records `primaryAgent: "cursor"` in the row.
- **Manual demo command:** `bun run deliver --plan <fixture-plan> --subagent codex-cli --primary claude execute <ticket>` against a fixture where codex-cli is intentionally unavailable (e.g., binary path overridden to a no-op). Observe the resulting `*-subagent-review.ledger.json` row contains `runnerKind: "claude-cli"`, `fallbackFrom: "codex-cli"`, `primaryAgent: "claude"`, and a sensible `runnerSelfReport`.

## Red

- Add tests covering:
  - `coerceCodexCliClassification`: given a fixture stdout containing `runnerStatus: completed` and a stderr blob containing rate-limit-like text but no authentic signal → outcome `completed` / `clean`, not `skipped`.
  - `coerceCodexCliClassification`: given an authentic rate-limit exit code or structured error → outcome `skipped` with `terminatedReason: rate_limit`.
  - `resolveSubagentSelection`: missing `--subagent` flag and missing `orchestrator.config.json:subagentRunner` → throws with a documented error message.
  - `resolveSubagentSelection`: `--subagent codex-cli` returns codex-cli with no fallback record.
  - `runSubagentReview`: with `--subagent codex-cli` and codex-cli unavailable, fallback fires; row records `runnerKind: claude-cli`, `fallbackFrom: codex-cli`.
  - `runSubagentReview`: with both runners unavailable, outcome is `skipped`; ledger preserves the original `subagentRequested: codex-cli` so the fallback attempt is auditable.
  - `recordPrimaryAgent`: free-form values like `cursor`, `composer`, `copilot` pass through unchanged; absent flag/config records `"unknown"`.
- Run `bun test`; confirm all new tests fail.
- Commit: `test(P14.02): runner selection, classification, and identity capture [red]`

## Green

- Rename `codex-exec` → `codex-cli` mechanically across:
  - `tools/delivery/subagent-runner.ts` (`SubagentRunnerKind`, `VALID_RUNNER_KINDS`, `commandForRunner`, etc.)
  - `tools/delivery/cli-runner.ts` (flag parsing, help text, error messages)
  - `scripts/soa-sync.sh` (prose mention at line 255 and the HEREDOC scaffold template at lines 220-235)
  - Skill prose in `.agents/skills/**` that references runner names
  - Docs in `docs/template/**` that reference runner names
  - Any test fixtures using the old name
- Update the **consumer-repo `orchestrator.config.json` scaffold template** inside the `scripts/soa-sync.sh` HEREDOC (lines 220-235) so newly-installed consumer repos receive the Phase 14 shape. Specifically:
  - Add `"primaryAgent": "unknown"` to the scaffold so the field is visible to operators on first install and they can edit it to `claude`, `codex`, `cursor`, `composer`, etc.
  - Do **not** scaffold a default `subagentRunner` value. The product plan locks "SoA ships no built-in silent default" — first `/soa execute` in a fresh consumer repo should error with the documented "specify `--subagent` or set `subagentRunner` in `orchestrator.config.json`" message, teaching the operator the contract before any review runs.
- Update the **sample JSON config block** in `docs/template/delivery/delivery-orchestrator.md` to show the Phase 14 shape (with `subagentRunner: "codex-cli"` and `primaryAgent: "claude"` as illustrative example values, plus a short paragraph explaining the precedence and the no-silent-default contract).
- Implement `resolveSubagentSelection(flag, configField)`:
  - flag set → return flag value
  - flag unset, configField set → return configField value
  - both unset → throw with documented error message pointing at cross-family best-practice docs
- Implement `resolvePrimaryAgent(flag, configField)`:
  - flag set → return flag value (free-form passthrough)
  - flag unset, configField set → return configField value
  - both unset → return `"unknown"`
- Implement codex-cli classification:
  - Parse the model's `runnerStatus` line from the report trailer when present
  - Record `runnerSelfReport: <trailer value | null>` on every row
  - Define an `authenticRateLimitSignal` predicate per runner in runner config
  - When stderr contains rate-limit-shaped text but the predicate returns false, classify as `completed` not `rate_limit`
- Implement the fallback chain in `runSubagentReview`:
  - Try the operator-specified subagent first
  - If unavailable per the rich predicate, try the other configured runner
  - Record `fallbackFrom: <originally-requested>` when fallback fires
  - Both unavailable → `outcome: skipped` honestly
- Update ledger writers to populate `primaryAgent`, `runnerSelfReport`, and `fallbackFrom` on every row.
- Remove `--preferred-runner` flag and its config field.
- Run `bun test`; confirm green.
- Commit: `feat(P14.02): operator-explicit subagent selection, codex-cli rename, classification fidelity`

## Refactor

- Extract the rate-limit predicate into a per-runner config block if the codebase currently inlines it.
- Extract `resolveSubagentSelection` and `resolvePrimaryAgent` into a single `resolveRunnerContext` if both functions share parsing surface (flag + config + default).
- Only refactor what you touched.

## Review Focus

- **Boundary between "completed with stderr noise" and "authentic rate-limit."** This is the load-bearing classification boundary. Verify the codex-cli authentic-signal predicate references specific exit codes / structured fields, not stderr text matching. A regression here reproduces the codogotchi P2 audit failure.
- **Error message when `--subagent` is missing.** It should be unambiguous: name the flag, name the config field, point at the best-practice docs. A vague error reproduces the "operator-hostile" failure mode the hard-error choice is meant to avoid.
- **Free-form `--primary` validation.** Confirm the validator does not constrain values beyond "is a non-empty string or absent." Trying to enforce a known-list silently rejects `cursor`, `composer`, etc. — the persona this flag is designed to support.
- **`fallbackFrom` semantics on `skipped`.** When both runners fail, what does the row record? The Outcome says `fallbackFrom: <originally-requested>` even on the skipped row, so the fallback attempt is visible. Verify the writer does this.
- **Removal of `--preferred-runner`.** Did any test fixture still pass the old flag? Any skill/doc still document it? P14.04's rename ticket touches docs again, but P14.02 should clear the runtime surface.
- **Consumer-repo scaffold pedagogy.** The `scripts/soa-sync.sh` HEREDOC ships with `primaryAgent: "unknown"` present but `subagentRunner` deliberately absent. Verify a fresh `/soa install` followed by `/soa execute` produces the documented "specify `--subagent` or set `subagentRunner`" hard error rather than silently picking a default. This is the load-bearing first-touch experience for the no-silent-default contract.
- **Sample config block accuracy.** The JSON block in `docs/template/delivery/delivery-orchestrator.md` is what operators copy-paste when troubleshooting. Verify its illustrative values are syntactically valid JSON and that the surrounding prose explains the `--subagent` flag > config field > error precedence in one short paragraph.
- **Public API shape:** `resolveSubagentSelection` and `resolvePrimaryAgent` signatures should accept dependency-injected config readers so tests can exercise the flag/config/default precedence without touching disk.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `coerceCodexCliClassification` / `resolveSubagentSelection` / `resolvePrimaryAgent` / `runSubagentWithFallback` import failures plus the missing `--subagent`/`--primary` flag handling.

Why this path:

- Added pure helpers under `tools/delivery/subagent-runner.ts` so the contract (flag > config > error; free-form primaryAgent; authentic-signal-only rate-limit; explicit fallbackFrom recording) is testable without touching disk, matching the "Public API shape" requirement in Review Focus.
- Codex-cli authentic-rate-limit predicate is structured-only: exit code 7 OR a quoted JSON-shaped `{"error":"rate_limited"}` / `rate_limit_exceeded` / `RATE_LIMIT(_EXCEEDED)?` token. Stderr prose like "you may have hit your rate limit" no longer triggers `skipped` — that was the codogotchi P2 misclassification.
- `runSubagentWithFallback` always preserves the originally-requested kind in `fallbackFrom` on the `failed_all` path, so the skipped row remains auditable per the Review Focus item.
- Scaffold (`scripts/soa-sync.sh`) ships `primaryAgent: "unknown"` but deliberately omits `subagentRunner`, so first `/soa execute` in a fresh repo errors with the documented contract message before any review runs.

Alternative considered: defining authentic rate-limit predicates as inline matchers in the runner loop. Rejected — keeping them as a single per-runner helper (`isCodexCliAuthenticRateLimit`) made the boundary between "completed with stderr noise" and "authentic rate-limit" trivially auditable and isolated future codex-cli signal evolution to one function.

Deferred: nothing material. (Initial draft of this rationale deferred the claude-cli authentic-rate-limit predicate, but the very first advisory subagent run misclassified itself — the review's own prose mentioned "rate limit" while probing the codex-cli predicate, and the legacy `classifyRunnerTermination` prose heuristic collapsed it to `skipped`. The ticket spec explicitly says "claude-cli's authentic signal is parsed analogously," so the symmetric `coerceClaudeCliClassification` was added in a `[subagent-review]` patch before the PR opened.)

Contract note: `--preferred-runner` is removed (hard error with named resolution). `subagentRunner` is now a config field, but it has no resolved default — `resolveOrchestratorConfig` passes the raw value through and `resolveSubagentSelection` raises when both flag and field are absent.
