# Phase 11 Retrospective — Subagent-review Class Absorption and Artifact Honesty

## 1. Scope Delivered

Five tickets shipped across a stacked PR chain:

- **P11.01** ([PR #38](https://github.com/cesarnml/son-of-anton/pull/38)) — Structured `SubagentRunnerArtifact` schema (`ticket`, `invocations[]`, per-invocation `runnerKind`, `reviewedHeadSha`, `outcome`, `completedAt`, `terminatedReason`, `findings[]`, `probedSurfaces[]`, `patches[]`); `buildRunnerInvocation`, `buildRunnerArtifact`, `appendInvocationToArtifact`, `readSubagentRunnerArtifact`; forward-compat adapter that reads legacy 4-field artifacts as a single `invocations[0]` with `terminatedReason: 'completed'`; on-disk fixtures under `tools/delivery/test/fixtures/legacy-subagent-runner/` derived from real codogotchi phase-01 artifacts. Subagent-review patches: `1f826ae` (`validateInvocation` / `isLegacyShape` tightened) and `a418440` (`terminatedReason=runner_unavailable` when all runners skipped).
- **P11.02** ([PR #39](https://github.com/cesarnml/son-of-anton/pull/39)) — Docs-only. Adversarial review template gained a "Diff-derived attack surfaces" sub-section enumerating the seven absorption-target classes with the coverage-mandate output form repeated per class; scope contract relaxed to "do not patch ticket docs; do read and surface drift in Findings"; patch discipline extended with the spec-permits-real-bug clause; required output extended with `runnerStatus` / `terminatedReason`. `son-of-anton-ethos` skill rewritten to describe the advisory-runner contract (subagent returns findings; primary agent applies patches with `[subagent-review]` suffix).
- **P11.03** ([PR #40](https://github.com/cesarnml/son-of-anton/pull/40)) — `subagent-review` recorder-mode CLI semantics (`subagent-review [clean|patched] <sha...>` appends an invocation and exits without subprocess); artifact-existence-at-HEAD as the idempotency key (matching non-skipped invocation = no-op); `--force` flag overrides idempotency only; `parseSubagentReviewArgs` / `decideSubagentReviewMode` extracted as pure helpers. Subagent-review patches: `d6f2bc0` (reject trailing positionals), `74877a7` (accept patch commits in recorder mode), `77eec6c` (validate state transition before recorder append).
- **P11.04** ([PR #41](https://github.com/cesarnml/son-of-anton/pull/41)) — Termination-honesty contract: `SpawnResult.terminatedReason` populated by lightweight stdout/stderr signature detection (rate_limit / sandbox_denied); `decideSubagentOutcomeFromRunner` overrides `clean` → `skipped` when termination was not `completed`; `shouldFallbackToOtherRunner` restricts auto-fallback to `unavailable | timeout` (ambiguous output exits honestly). Subprocess wait is structurally guaranteed by `spawnSync`; the test pins the post-exit porcelain ordering. Subagent-review patch: `72330b4` (re-raise `spawnSync` ENOENT, tighten rate-limit regex).
- **P11.05** (this ticket) — Exit-condition walk, README drift fix (the "Findings go to you" / autonomous-patcher claim contradicted P11.02's ethos correction), product plan delivery status updated to Shipped, this retrospective.

## 2. What Went Well

**Schema-first sequencing was load-bearing.** The product plan flagged "SoA-delivering-itself recursion" as risk #4 and prescribed P11.01 → P11.03 → P11.04 with P11.02 in parallel. That ordering paid for itself: P11.01 stabilized the artifact shape before P11.03 changed the CLI's invocation model, so when P11.03 broke its own state-transition validation (caught in subagent-review patch `77eec6c`), the artifact contract it appended to was already battle-tested. A flatter schedule would have compounded a CLI bug with an artifact-shape bug on the same PR.

**The forward-compat adapter shipped against real on-disk fixtures, not synthesized examples.** P11.01's fixtures are sanitized copies of actual codogotchi phase-01 4-field artifacts. The adapter's coverage is grounded in shapes consumers will hand it, not in shapes the author imagined. This caught one degenerate case (`completedAt: ''` from a real artifact) that a synthesized fixture would not have surfaced.

**Splitting `buildRunnerArtifact` and `buildRunnerInvocation` was the right shape.** P11.01's Rationale notes the choice explicitly: per-invocation construction is its own call site, artifact construction is its own call site, and the append helper handles legacy-on-disk and new-on-disk in one place. Downstream P11.03 and P11.04 consumed each surface without overloading.

**Pure-function extraction made P11.04 testable without a full handler refactor.** `decideSubagentOutcomeFromRunner` and `shouldFallbackToOtherRunner` are 10-line policy decisions. Lifting them out of the CLI loop let the four termination-honesty invariants land as red tests at the helper level instead of as integration tests over the whole subagent-review case. P11.03 set this pattern with `parseSubagentReviewArgs` / `decideSubagentReviewMode`; P11.04 reused the shape without architectural debate.

**The advisory-runner ethos correction was a docs-only ticket that caught a contract drift before it ossified.** P11.02 rewrote both the template and the ethos skill in one stroke so the reader-facing contract matches the implementation contract (subagent advises; primary agent patches). Catching it at the same time the runner-termination work landed prevented "the ethos says one thing, the code does another" from persisting another phase.

## 3. Pain Points

**Subagent-review patches landed on P11.03 in a sequence that suggested the helper extraction was under-tested before the first review.** Three subagent-review patches (`d6f2bc0`, `74877a7`, `77eec6c`) covered: trailing-positional rejection, patch-commit acceptance in recorder mode, and state-transition validation before append. Each is a legitimate finding the adversarial reviewer caught, but the sequence implies the `parseSubagentReviewArgs` / `decideSubagentReviewMode` pair shipped with thin red coverage on the argument-space edges. **Avoidable waste:** the red step could have enumerated invalid-arg permutations more aggressively before green.

**README drift was easy to miss because P11.02 only touched the ethos skill and template.** The README's "Findings go to you" claim (P10.04 vintage) survived P11.02 untouched because the ticket scope did not name it. P11.05's check caught it, but had P11.02 listed user-visible docs explicitly in its scope, it would have shipped with the rest of the contract correction instead of trailing into P11.05. **Avoidable waste:** the doc-only ticket's surface list should include the README when it makes claims about the contract being rewritten.

**Phase-10 retrospective's `validateRunnerArtifact` follow-up landed quietly inside P11.01.** Phase-10 flagged "minimum field validation in `validateRunnerArtifact`" as a follow-up. P11.01's subagent-review patch `1f826ae` ("tighten validateInvocation and isLegacyShape") effectively closed that — but the linkage between the follow-up and the patch is not recorded in either retrospective. **Expected cost:** the follow-up was structural enough to absorb organically, but the audit-trail bias of this phase suggests we should be naming these forward-links explicitly.

## 4. Surprises

**`spawnSync`'s synchronous nature made the porcelain-ordering invariant a tautology — but the test pins it anyway.** P11.04's red test for "porcelain sampled after subprocess exit" is structurally enforced by `spawnSync` returning after the child exits. The test still exists and asserts the contract because future refactors to async `spawn` would silently violate the ordering. This is the right shape: pin the invariant at the test level even when the current implementation makes it free.

**The `terminatedReason` honesty guard chose `skipped` over a new outcome literal.** P11.04's Rationale flags the design choice explicitly: rather than introducing `'incomplete'` as a fourth outcome (which would force every consumer's exhaustive match to update), the CLI overrides `clean` → `'skipped'` and carries the failure mode through `terminatedReason`. The surprise is that the existing `clean | patched | skipped` union already had the right granularity once `terminatedReason` carried the why.

**`--force` semantic scope is intentionally narrower than its name suggests.** P11.03 and P11.04 both call this out: `--force` skips the artifact-existence-at-HEAD idempotency check, nothing else. The termination-honesty guard, doc-write-boundary check, and state-transition validation all still fire. The risk we considered: a future contributor reads `--force` as "bypass safety" and adds a guard bypass to it. The Rationale notes are the only thing pinning the contract; consider an explicit comment in `decideSubagentReviewMode` if this surfaces again.

**The advisory-runner contract change in P11.02 is reader-facing but the runtime contract did not move.** The runner already returned findings and the primary agent already applied patches in practice — the ethos doc just claimed otherwise. P11.02 is a contract-clarification ticket, not a behavior change. This surfaces a class: shipped behavior can outrun shipped docs by a full phase before the gap closes, and the only mechanism we have for catching it is the next phase's plan calling it out.

**The seven diff-derived classes are still a hypothesis.** P11.02 enumerated them in the template; phase-11 does not validate that subagents actually catch more in practice when directed at them by name. The product plan acknowledges this: "Validation of the absorption claim — does the expanded template actually produce CR-class catches in practice — happens in downstream consumer phases." The retrospective records the prediction; consumer phases must record the evidence.

## 5. What We'd Do Differently

**Name documentation surfaces explicitly in doc-only tickets' scope.** P11.02's surface list was "the template + the ethos skill." The README claim P11.05 caught was a foreseeable miss: any contract correction should list every doc making claims about that contract. The original reasoning was scope discipline — keep doc-only tickets narrow. The new information is that "narrow scope" applied to surface enumeration is different from "narrow scope" applied to claim coverage; the former is correct, the latter creates drift.

**Cross-reference phase-N retrospectives' follow-ups explicitly when phase-N+1 tickets absorb them.** P11.01's `validateRunnerArtifact` tightening closed a phase-10 follow-up. Neither retrospective links the two. A one-line "Closes phase-10 follow-up X" in P11.01's Rationale would have made the audit trail honest at the patch level — which is exactly the boundary phase-11 was built to strengthen.

**Front-load argument-space red tests for CLI-arg-parsing extractions.** The three P11.03 subagent-review patches covered argument-space edges that a more exhaustive red step would have surfaced. The original reasoning was "ship the helper extraction with the canonical-case red test and let adversarial review surface the edges." That worked, but it leans on the subagent doing the author's red work. Cheaper to enumerate `[]`, `[wrong-count]`, `[wrong-token]`, `[trailing-positional]` at red time.

## 6. Net Assessment

The stated goals were achieved on the SoA-repo side. The subagent-review CLI writes a structured artifact carrying findings text, probed surfaces, patches, and per-invocation history; the runner artifact's 4-field shape is gone from the type definition; the forward-compat adapter reads real legacy artifacts against on-disk fixtures; `outcome: clean` cannot be recorded for a non-`completed` termination; recorder mode short-circuits subprocess invocation; the ethos doc and adversarial template describe the actual contract.

The absorption claim — that naming the seven diff-derived classes in the template materially broadens subagent coverage in practice — is **not** validated by phase-11. The product plan was explicit that downstream consumer phases own that evidence. Phase-11 is a precondition phase: it makes the validation possible without claiming the result.

Net: the audit-trail gap that codogotchi phase-01 surfaced is closed at the artifact layer. Whether the broadened template absorbs CR-class findings in production is an open empirical question.

## 7. Follow-Up

- **Validate the absorption claim in the first consumer phase shipped against this template.** The seven diff-derived classes are now named in the template. The next consumer phase to ship subagent-review with this template should record, in its own retrospective, whether the subagent caught classes the prior template missed. Naming the validation gate explicitly here so the next consumer retrospective has an obligation.
- **Add a contract comment to `decideSubagentReviewMode` pinning the narrow scope of `--force`.** Currently the contract lives in P11.03's and P11.04's Rationale notes only. A four-line comment at the function would survive future contributor reads better than the Rationale trail.
- **Phase-12 picks up post-red gate placement.** Already a deferred item in the product plan; calling it out here so the closeout audit trail keeps the link visible.
- **Phase-13 picks up baseline-policy persistence, review JSON Biome-format reformat, worktree filesystem refresh on `advance` cook-handoff, `subagent-review` positional-arg parsing fix, and `poll-review` "Review skipped" detection.** All deferred from phase-11 per the product plan; named here so phase-13 inherits a concrete list, not a recall task.
- **Future doc-only tickets that correct a contract claim should enumerate every doc surface making that claim.** Process follow-up: when `/soa decompose` produces a doc-only ticket whose Outcome includes "the X skill describes Y correctly," the ticket-scope check should grep for the prior incorrect claim across `README.md`, `docs/template/overview/`, and `docs/template/delivery/` before approving the scope.

---

_Created: 2026-05-20. PRs #38–#41 merged via closeout-stack; PR for P11.05 open pending developer approval._
