# Phase 21 — Subagent-Review Contract and Runner Fidelity

> Replaces the heading-parsed subagent-review report with a tag-based machine-read contract, makes recorded outcomes honest, fixes the fallback chain, adds per-platform model/effort control with ledger fidelity, notifies review outcomes, and absorbs codogotchi's review-gap lessons into the adversarial prompt.

## Epic

Product plan: `docs/product/plans/phase-21-subagent-review-contract-and-runner-fidelity.md`

Origin issue: #78
Origin issue: #83
Origin issue: #84
Origin issue: #87
Origin issue: #105

> Multi-issue note: `parseOriginIssueNumber` honors only the first line until
> P21.06 lands multi-issue support. The final ticket's PR must carry one
> `Closes #<N>` bullet for each of the five issues.

## Product contract

- Machine-read regions of `subagent-review.report.md` (actionable findings, advisory observations, runner termination) are extracted by balanced tags per `notes/public/subagent-report-parser-contract.md`; a malformed or empty-but-not-`None` block warns loudly at `subagent-review` record time.
- A ledger outcome of `clean` guarantees the report's actionable-findings block is empty; a completed review with findings records `completed_with_findings`.
- A preferred runner that spawns but produces no usable review (`runner_failed`, `rate_limit`, `sandbox_denied`) advances the fallback chain; `skipped` is reserved for exhaustion of every runner.
- Operators pin model and thinking effort per platform via `subagentRunnerOptions` config or flat `--subagent-model`/`--subagent-effort` flags; invalid values fail fast; ledger rows record what actually ran.
- The developer is notified of each recorded subagent-review outcome, with clean vs. findings clearly differentiated.
- A phase resolving multiple GitHub issues closes all of them via generated `Closes` bullets on the final ticket's PR.
- `adversarial-review-template.md` carries every codogotchi review-gap class that met the ≥2–3× promotion bar, backed by a written analysis accounting for every review-reachable ledger row.

## Grill-Me decisions locked

- All six scope items in one phase → dependency chain (tag contract → honesty → notification) and shared files (`subagent-runner.ts`) make one stack cheaper than two phases; developer overrode the option to split #84 out.
- Tag contract covers all three machine-read regions (not just advisory observations) → #83's cross-check must build on the tag parser, not the heading grammar it replaces.
- Forward-only parser, no legacy heading fallback → the record-time zero-parse loud floor plus a documented upgrade rule cover the transition; heading inference is the failure surface being removed.
- Outcome label is `completed_with_findings` (not `findings`) → developer preference for the self-documenting form; schema version bumps to 2 with tolerant v1 reads.
- #78 surface: per-platform `subagentRunnerOptions` config map + flat CLI flags applying to the requested runner only; fallback runners resolve from config → keeps the common case simple and stays coherent under the #105 fallback chain.
- #105 fallback advances on `runner_failed`, `rate_limit`, `sandbox_denied`; `advisory_violation` records honestly and stops → violation is a contract breach signal, not a platform-local failure.
- Multi-issue Origin close mechanism built in-phase (P21.06) → manual closes are an unrecorded side-channel step; this five-issue cluster proves multi-issue phases recur.
- Retrospective required → durable parser-contract boundary + two operator-workflow changes.

## Ticket Order

1. `P21.01 Tag-based report contract: strict parser, template rewrite, record-time loud floor`
2. `P21.02 Outcome honesty: completed_with_findings cross-check and terminology pass`
3. `P21.03 Fallback advances on ran-but-failed runners`
4. `P21.04 Per-platform model and effort selection with ledger fidelity`
5. `P21.05 Subagent-review outcome notification`
6. `P21.06 Multi-issue Origin close`
7. `P21.07 Review-gap ledger mining, clause promotion, and phase docs`

## Ticket Files

- `ticket-01-tag-contract-strict-parser-loud-floor.md`
- `ticket-02-outcome-honesty-completed-with-findings.md`
- `ticket-03-fallback-on-ran-but-failed.md`
- `ticket-04-per-platform-model-effort-selection.md`
- `ticket-05-subagent-review-notification.md`
- `ticket-06-multi-issue-origin-close.md`
- `ticket-07-review-gap-mining-and-phase-docs.md`

## Exit Condition

A delivery run on this repo completes a subagent review whose report is extracted purely by tag contract, records an outcome that matches the report body, notifies that outcome, and shows resolved model/effort on the ledger row. Tickets P21.02 onward are themselves reviewed under the contract P21.01 ships into the stack — the phase dogfoods its own gate. A deliberately broken preferred runner yields a fallback attempt instead of `skipped`. The final PR closes #78, #83, #84, #87, and #105, and `adversarial-review-template.md` carries the promoted `control-signal-starved-by-change-gated-callback` clause plus any other class the verified counts qualify.

## CI Baseline

> Baseline recorded: 2026-07-16 — 15 pre-existing failures: all in `tools/delivery/test/p17-02.test.ts`, `p17-03.test.ts`, `p17-04.test.ts` (codogotchi gate-emission tests read the legacy `gate.json` location and fail with ENOENT against the current per-session gate files; reproduced on clean `main` at 4d50c13). Remaining 721 tests pass. These failures do not block phase-21 tickets; a separate fix is queued outside this phase.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- P21.02 must not start before P21.01 lands in the stack (cross-check builds on the tag parser); P21.05 must not start before P21.02 (notification carries the honest label).
- P21.03 and P21.04 both modify `subagent-runner.ts`; they stack sequentially, never in parallel worktrees.
- P21.07 is the final ticket; its PR body carries the five `Closes` bullets enabled by P21.06.

## Explicit Deferrals

- Legacy heading-format parsing fallback — rejected by decision: heading inference is the silent-failure surface being removed; the loud floor plus upgrade rule cover the transition.
- Cross-family review enforcement as a hard gate — remains operator choice plus ledger audit (per #78 scope).
- Auto-selecting model/effort from ticket size or diff stats — revisit once ledger rows carry the model/effort data P21.04 adds.
- Red/green TDD gate notifications — explicitly excluded by #87 as noise; owned by the animation layer.
- Phase-level integration review pass — the promotion-queue caveat is real but it is a new review lane needing its own design, not a prompt clause.
- Discord notification transport — tracked separately as #86.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- P21.01's template rewrite changing subagent behavior in a way that breaks the dogfooded reviews of later tickets — stop and surface rather than hand-patching reports.
- The #84 analysis finding the promotion-queue counts wrong in a way that changes which classes qualify — stop and confirm promotion decisions with the developer before editing the template.

## Phase Closeout

Retrospective: required
Why: This phase replaces a durable boundary (the report parser contract every future review crosses) and changes operator workflow twice (notifications, model/effort config); the parser-contract note makes a falsifiable prediction — that the tag contract plus loud floor ends the drift arms race — and the retrospective is where that verdict lands.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-21-subagent-review-contract-and-runner-fidelity-retrospective.md`
