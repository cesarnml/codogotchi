# Phase 11: Subagent-review class absorption and artifact honesty

**Delivery status:** Shipped. Five-ticket stack (P11.01–P11.05) delivered via [`docs/product/delivery/phase-11/implementation-plan.md`](../delivery/phase-11/implementation-plan.md). Retrospective at [`docs/product/retrospectives/phase-11-subagent-review-class-absorption-and-artifact-honesty-retrospective.md`](../retrospectives/phase-11-subagent-review-class-absorption-and-artifact-honesty-retrospective.md).

## TL;DR

**Goal:** Make subagent-review absorb the bulk of CodeRabbit's class repertoire and produce honest, auditable persisted artifacts — so external CR becomes an occasional confirmation gate, not the only place those classes get caught.

**Ships:**

- Expanded adversarial review template that explicitly directs the subagent at the seven diff-derived finding classes CR currently catches and the template currently does not name.
- Flag-only treatment of doc-vs-code drift in ticket Rationale (subagent reads ticket docs and surfaces drift in Findings without patching).
- Patch discipline clarified to cover real correctness bugs the ticket spec literally permits ("spec-permits-real-bug" case).
- Single programmatic-subprocess invocation per `subagent-review` CLI command, with artifact-existence-at-HEAD as the idempotency key.
- Recorder-mode CLI semantics: when the primary agent supplies an outcome, the CLI records and exits without invoking a runner.
- Structured runner artifact carrying findings text, probed-surfaces list, patches list, and per-invocation history (replaces today's 4-field shape).
- Runner-termination honesty: the runner reports its own termination state, and the CLI refuses to record `clean` when the runner did not actually complete a review.
- Ethos doc updated to match the advisory-runner reality (primary agent applies patches; subagent advises).
- Forward-compatible schema adapter so consumers mid-phase can update without artifact migration ceremony.

**Defers:**

- Post-red gate placement refactor (phase-12).
- Baseline-policy persistence, filesystem-hygiene fixes (review JSON format, worktree filesystem refresh on cook handoff), and small CLI fixes (positional-arg parsing, poll-review `skipped` detection) (phase-13).
- Structured triage `findingDecisions` schema (`patched`/`pushed_back`/`deferred`) — independent of the absorption work; ships in a later phase.
- Template revision requiring push-back rationale to name the specific spec clause (Rev 13) — pairs with the structured triage schema; ships when that does.

---

This phase exists because the consuming-repo retrospective for codogotchi phase-01 (`notes/private/codogotchi-phase-01-son-of-anton-retrospective.md`) shipped three orthogonal claims with hard evidence across 21 tickets and five appendices. The workflow path (stacked PRs, worktree isolation, TDD enforcement, advance/handoff materialization) earned its keep. The audit-trail path did not — every `*-subagent-runner.json` in the phase persisted as four fields (`runnerKind`, `reviewedHeadSha`, `outcome`, `completedAt`) with no findings text, even on tickets where the subagent caught load-bearing bugs (P1.18 caught four real correctness issues; the artifact recorded `{outcome: "clean"}`). And the review path catches real bugs but the subagent's coverage is structurally narrower than it needs to be — CR consistently catches classes the adversarial template does not direct the subagent at, while external CR is $1/PR with a 1-PR/hour free-tier ceiling, making CR-on-every-PR uneconomical.

Phase-11 closes the audit-trail gap and broadens subagent coverage so subsequent consumer phases can ship with `--pr-review-policy disabled` as a reasonable default on narrow-surface tickets, reserving external CR for high-stakes PRs and for the one finding class CR catches structurally (orchestrator-meta findings on freshly-persisted JSON artifacts the subagent never sees).

## Phase Goal

This phase should leave the product in a state where:

- A consumer running `subagent-review` produces a persisted artifact that contains the subagent's findings text, the surfaces it probed (with `[probed]`/`[N/A — reason]`/`[blocked — missing-input]` coverage statements), patches applied, and the runner's own termination reason — auditable months later without chat-history recovery.
- The adversarial review template directs the subagent at named diff-derived classes — output stability across schema-version drift, CLI flag/arg symmetry, error-class breadth in `catch` blocks, defensive layering at module boundaries, cross-file atomicity windows, test-contract strength, and doc-vs-code drift in the ticket Rationale — alongside the existing ticket-spec-derived invariant surfaces.
- The CLI invokes exactly one subprocess per `subagent-review` invocation. Repeat invocations against the same HEAD are no-op recorders. Operator-supplied outcomes (`subagent-review <ticket> [clean|patched] <sha>`) record without firing a subprocess at all.
- The `son-of-anton-ethos` skill describes the actual contract: subagent-review returns findings, primary agent applies patches and commits them with `[subagent-review]` suffix.
- Consumers with in-flight phases at update time keep working — old 4-field artifacts read through a forward-compatible adapter; no migration command required.

## Committed Scope

Two distinct surfaces of work, both in service of the same goal. Cross-references in brackets cite the patch IDs from `notes/private/phase-11-soa-patch-plan-from-codogotchi-p1-retro.md` so decomposition can pull straight through.

### Adversarial review template

- Add a "Diff-derived attack surfaces" sub-section to the template's existing "Attack surfaces" section. The section requires the primary agent to enumerate, by name, surfaces drawn from the seven absorption-target classes. Each surface uses the coverage-mandate output form (`[probed]` / `[N/A — reason]` / `[blocked — missing-input]`). [M1]
- Relax the template's scope contract from "skip ticket docs" to "do not patch ticket docs; do read the Rationale and contract docs and surface doc-vs-code drift in Findings for human review." [M2]
- Extend the "Patch discipline" directive with a third patch-when clause: patch when the ticket's stated contract literally permits a behavior that is nevertheless unsafe in production (the "spec-permits-real-bug" case). [Rev 12]
- Require the subagent to emit a `runnerStatus` / `terminatedReason` field as part of its required output, so the CLI has an explicit termination-state claim to read instead of inferring from a porcelain check. [Rev 15]

### CLI, artifact, and ethos contract

- Replace the runner-artifact's four-field shape with a structured schema. Required fields: `ticket`, `invocations[]` where each invocation carries `runnerKind`, `reviewedHeadSha`, `outcome`, `completedAt`, `terminatedReason`, `findings[]`, `probedSurfaces[]`, `patches[]`. `invocations[]` is append-only across CLI invocations for the same ticket. [M5]
- Add a `terminatedReason` field with values `completed | rate_limit | sandbox_denied | runner_unavailable`. The CLI refuses to record `outcome: clean` for any non-`completed` terminatedReason. [M6]
- Make artifact-existence-at-current-HEAD the idempotency key for `subagent-review`. When a valid artifact for the current HEAD exists, the CLI exits as a no-op recorder. A `--force` flag overrides for the legitimate "re-review after follow-up patches" case. [M3 derived from code-read correction]
- Recorder-mode default: `subagent-review <ticket> [clean|patched] <sha>` appends a recorder-mode entry to `invocations[]` and exits. Never invokes a subprocess. [M4]
- Keep the existing same-command auto-fallback only for hard binary-availability failures (`unavailable` from `tryRunner` — preferred binary not on PATH) and timeouts. Do not extend auto-fallback to cover ambiguous runner output (rate-limit body in stdout, sandbox-denial-as-result, exit-code-0-with-no-work). Those exit honestly via `terminatedReason` and let the primary-agent loop decide whether to retry. [Refined from M3/M6 code read]
- Wait for the runner subprocess to exit before sampling `git status --porcelain` for outcome detection. Close the orphan-edit race window where the runner can keep writing after porcelain reads clean. [M8]
- Update the `son-of-anton-ethos` skill text. Today it claims the review subagent "reviews and patches its own findings autonomously"; the new text reflects the advisory contract — the subagent returns findings; the primary agent applies and commits patches with `[subagent-review]` suffix; exactly one subagent-review invocation per ticket via programmatic subprocess. [M15]
- Ship a forward-compatible schema adapter that reads legacy 4-field artifacts as `invocations: [{...legacy fields, terminatedReason: 'completed', findings: [], probedSurfaces: [], patches: []}]`. No migration command; mid-phase consumer updates are safe. [Derived from Q5 resolution]

## Explicit Deferrals

- **Post-red gate placement (phase-12).** Six tickets in codogotchi phase-01 paid the post-red-after-implement tax. The fix is a state-machine change with phase-level visibility implications and belongs in its own phase. Phase-11 does not touch `post-red` ordering.
- **Baseline-policy persistence and resume-prompt flag rendering (phase-13).** Roughly 32 redundant `--baseline run-policy` flag invocations in one codogotchi phase-01 thread. Real friction, but independent of the review apparatus.
- **Review JSON Biome-format reformat (phase-13).** Five reproductions across codogotchi phase-01 of orchestrator-written review JSONs reformatted on first repo-format pass. Hygiene fix; commits-in-repo-format-or-gitignore-them.
- **Worktree filesystem refresh on `advance` cook-handoff (phase-13).** Two near-misses on missing prior-ticket review files in codogotchi P1.20/P1.21 worktrees. Cleanup; not the review apparatus.
- **`subagent-review` positional-arg parsing fix and `poll-review` "Review skipped" body-text detection (phase-13).** Small CLI fixes; ride along with the phase-13 hygiene work.
- **Structured triage `findingDecisions` schema (later).** Replacement of the free-text triage `note` field with a structured `{threadId, decision, rationale}` triple. Independent of the absorption work and worth its own product-plan-level discussion when it surfaces.
- **Template Rev 13 (push-back rationale must name spec clause).** Pairs with the structured triage schema above; ships when that does. Out of scope here.
- **Cross-ticket Rationale-encoded forward-dependency tooling, operator-intent-vs-runtime consistency lint, mid-phase `.env` propagation, `chore(delivery)` commit-title disambiguation, followups-tracking artifact (N-tier items).** All cataloged in the synthesis artifact under NICE TO DO / OPTIONAL. None block phase-11's goal.
- **The orchestrator-meta findings class** (CR catching bugs in the orchestrator's own persisted JSON — `vendor: null`, `outcome: clean` vs paused-vendor evidence, internal-state leak in fetch artifact). Structurally exclusive to post-PR review because the artifacts do not exist when the subagent runs. External CR retained as an occasional opt-in gate for this class; phase-11 does not attempt to absorb it.

## Exit Condition

When phase-11 is done, the following are demonstrably true:

- The adversarial review template at `docs/template/delivery/adversarial-review-template.md` contains a "Diff-derived attack surfaces" sub-section enumerating the seven absorption-target classes, the relaxed scope contract that flags (but does not patch) doc-vs-code drift, the extended patch-discipline directive covering spec-permits-real-bug, and the required `runnerStatus` / `terminatedReason` output field.
- `tools/delivery/subagent-runner.ts` exports a structured `SubagentRunnerArtifact` schema with `ticket`, `invocations[]`, and all per-invocation fields named in the Committed Scope. The 4-field legacy shape is gone from the type definition and is reached only through the forward-compat adapter.
- `tools/delivery/cli-runner.ts`'s `subagent-review` case writes the structured artifact, treats artifact-existence-at-HEAD as the idempotency key, supports recorder-mode for operator-supplied outcomes, waits for subprocess exit before porcelain sampling, and refuses to record `outcome: clean` for non-`completed` `terminatedReason`.
- The `son-of-anton-ethos` skill text describes the advisory-runner contract correctly.
- The forward-compat adapter handles real codogotchi phase-01 4-field artifacts as test fixtures; tests pass.
- `bun run ci` is green; spellcheck includes any new terminology introduced in the template.

Validation of the absorption claim — does the expanded template actually produce CR-class catches in practice — happens in downstream consumer phases. Phase-11 closes when the SoA-repo-level deliverables ship and the retrospective records the prediction.

## Retrospective

`required` — phase-11 changes the runner-invocation contract (durable boundary), introduces a structured persistence schema (durable boundary), changes the agent-facing ethos contract (operator workflow change), and underwrites phase-12 and phase-13 with a stable artifact layer (later-phase assumption). The retrospective is written at phase-11 closeout against the SoA-repo-level deliverables; downstream validation of the absorption claim happens organically in consuming repos and feeds future targeted improvements.

---

## Risk envelope

Five risks worth naming at plan time:

1. **The absorption claim doesn't hold in practice.** The enumerated seven-class checklist may not produce the expected catches when a real subagent walks a real diff. Mitigation: the checklist is text-only and trivially iterable in a follow-up phase; failure surfaces in the next consumer phase's retro.
2. **Forward-compat adapter edge cases.** Real codogotchi phase-01 4-field artifacts may exercise paths the adapter doesn't handle. Mitigation: test the adapter against actual on-disk artifacts as fixtures before phase close.
3. **HEAD-detection edge case in artifact-existence idempotency.** Primary-agent commits between subagent run and artifact write could leave the artifact's `reviewedHeadSha` out of sync with the worktree's actual HEAD. Mitigation: the `--force` escape hatch covers it; decompose-time concern to validate.
4. **SoA-delivering-itself recursion.** Phase-11 ships subagent-review changes through subagent-review itself. A mid-phase bug in shipped artifact-schema or runner-contract code lands in in-flight tickets before it can be reverted. Mitigation: sequence the artifact-schema work (M5 + adapter) to land first and stabilize before the runner-contract change (M3/M4) lands. Decompose-time sequencing concern.
5. **External CR config drift on the consumer side.** The design assumes consumers run `.coderabbit.yaml` with `base_branches: '.*'` (the codogotchi phase-01 fix). Consumers without that change get zero CR coverage and the orchestrator-meta-findings class never fires. Mitigation: docs reminder in the phase-11 docs pass even though it is not a code change.
