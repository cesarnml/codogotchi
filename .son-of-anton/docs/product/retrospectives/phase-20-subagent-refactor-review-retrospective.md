# Phase 20 — Subagent Refactor Review Retrospective

## Scope delivered

Four stacked tickets, PRs #106–#109 (branches `agents/p20-01-config-types-template-refactor-suggestions-parser-reconciliation` through `agents/p20-04-advance-time-surfacing-remaining-docs`), all `done`, awaiting developer review before closeout:

- P20.01: `reviewPolicy.refactorReview` config validation, mirrored `TicketState` fields, `refactor-review-template.md`, a new `tools/delivery/refactor-review.ts` module with a `<refactor-suggestions>` tag parser and Condition A/B reconciliation independent of the adversarial gate's heading-based parser.
- P20.02: `write-subagent-refactor-review`, `subagent-refactor-review` (recorder + runner modes, `record-deferred`), `reconcile-subagent-refactor-review` — reusing the adversarial gate's generic runner-core primitives via a new `runProgrammaticSubagentReview` orchestration function rather than duplicating spawn/fallback logic.
- P20.03: wired the refactor gate into the actual sequence — a precondition guard on `write-subagent-adversarial-review`, `status`/`resolveVerifiedNextCommand` routing, and updated `delivery-orchestrator.md`/`tdd-workflow.md`.
- P20.04: `advance`-time surfacing of deferred refactor suggestions, `son-of-anton-ethos/SKILL.md` and `start-here.md` updates, and the design note's status flip to `IMPLEMENTED`.

Rollout ships `refactorReview: "disabled"` everywhere (including this repo's own config) — the feature exists but is off by default, matching the approved product plan.

## What went well

- **Mirroring an existing gate's shape caught most design questions before they became bugs.** Ticket 20.01's design doc explicitly tabulated every adversarial-gate concept against its refactor-gate analog (prompt file, CLI commands, ledger outcome vocabulary, reconciliation conditions). Working from that table meant most implementation decisions were "what does the analog do" rather than open design, which kept each ticket's actual new-decision surface small and reviewable.
- **Reusing generic primitives instead of duplicating them paid off exactly where the ticket predicted.** `subagent-runner.ts`'s `tryRunner`/`runSubagentWithFallback`/`decideAdvisoryRunnerOutcome`/`coerce*Classification` needed zero changes to support the refactor gate — only a new orchestration wrapper (`runProgrammaticSubagentReview`) was added. This is the reason P20.02's diff was additive-only and the existing adversarial-gate test suite needed no changes.
- **The adversarial subagent review gate caught real, ticket-specific bugs every single time it ran (4/4 tickets), not just style nits.** Each pass surfaced at least one demonstrable correctness gap: P20.01's parser misclassified an empty tag body as clean and had a reconciliation short-circuit that didn't check full path coverage; P20.02's write-detection missed timeout-before-fallback writes and same-path rewrites, and its prompt auto-builder could pass validation without real authorship; P20.03's `status` routing never actually pointed at the new commands (the gate was implemented but not reachable through the advertised happy path); P20.04's ledger reader crashed on structurally-corrupt-but-valid JSON. None of these were style — all were "the ticket's stated contract doesn't hold" findings.

## Pain points

- **A stray literal NUL byte silently corrupted `cli-runner.ts` mid-phase, and standard tooling (`grep`, `git diff`) hid it rather than surfacing it.** The file became "binary" from git's perspective after one `Edit` call produced `.join('\x00')` instead of `.join(' ')`; every subsequent `grep` on that file returned zero matches with no error, which read as "the code isn't there yet" rather than "the tool is silently skipping a binary file." Root cause is unclear (possibly an encoding artifact in the edit-tool round-trip) but the detection method — noticing `grep` returned nothing for a string `python3` confirmed was present — is the reusable lesson: when a `grep` on a just-edited file returns suspiciously empty, check `file <path>` before assuming the edit didn't take.
- **The P20.03 finding (status routing never wired) was avoidable with more upfront cross-referencing.** The guard on `write-subagent-adversarial-review` was written and tested in isolation; `format.ts`'s `resolveVerifiedNextCommand` — the actual thing that tells an operator what to run next — was not checked against the new guard until the adversarial subagent caught the mismatch. This is an expected cost of implementing a guard and its corresponding "what should I run now" hint as separate concerns, but a checklist item ("does `status`'s next-command routing know about this new gate?") would have caught it before the review pass rather than requiring the review pass to catch it.

## Surprises

- **Reconciliation for the refactor gate needed to be _auto-invoked_ inside `write-subagent-adversarial-review`'s guard, not left as a separately-sequenced manual step, to actually be enforced.** The doc-level sequence says `reconcile-subagent-refactor-review` runs before `write-subagent-adversarial-review`, but nothing made that true until the guard itself called the reconciliation gate — mirroring how `open-pr` already auto-reconciles the adversarial ledger. This wasn't spelled out in the ticket 20.03 outcome and only became apparent while fixing the P20.03 subagent-review finding.
- **The two "silent tolerance" bugs in P20.01's tag parser (empty-body-as-None, unclosed-tag-as-trusted) were textbook instances of the exact failure class `notes/public/subagent-report-parser-contract.md` was written to prevent** — even though this phase built a brand-new, independent parser specifically to avoid inheriting the adversarial gate's parser drift history. Writing a fresh module didn't automatically avoid the failure mode the contract note warns about; only the adversarial subagent's adversarial reading of the new parser caught it.
- **Deferred refactor suggestions have no per-suggestion ledger persistence path yet.** Ticket 20.01 defined `RefactorSuggestionDecision`/`validateRefactorSuggestionDecision` (id/summary/decision/reason for individual suggestions), but no ticket in this phase ever wires per-suggestion adjudication into the ledger — only whole-ticket `record-deferred` (one reason per ticket) is reachable end-to-end. P20.04's advance-time surfacing reads whole-invocation `deferred` rows, which works for what's actually wired, but the per-suggestion type exists unused. Worth flagging before anyone assumes the finer-grained shape is live.

## What we'd do differently

- **Write the "does status/next-command routing need updating" check into ticket 20.02 or 20.03's Review Focus explicitly**, rather than relying on the adversarial subagent to discover it. The ticket docs' Review Focus sections were otherwise a good forcing function (each one flagged a real risk that the implementation had to address), but this specific cross-cutting concern (a new gate needs a routing update, not just a guard) wasn't named anywhere in the four tickets' text, even though it's a generalizable pattern any future "add a new pre-PR gate" phase will hit again.

## Net assessment

The phase achieved its stated goal: a working, tested, off-by-default `refactorReview: "runner_on_red"` gate that parallels the adversarial gate's mechanics without touching or duplicating its parser, fully wired into the actual command sequence (after the P20.03 fix) and into `advance`'s output. All four PRs are individually reviewable, CI-clean against the pre-existing 15-test baseline failure set (unrelated codogotchi gate tests), and each subagent-review pass produced real, addressed findings rather than rubber-stamped clean reports.

## Follow-up

- Wire per-suggestion `RefactorSuggestionDecision` adjudication into the ledger (currently only whole-ticket `record-deferred` is reachable) — or explicitly retire the unused type if the coarser granularity is deemed sufficient, so a future reader doesn't assume it's live.
- When `runner_on_red_strict` is eventually built, add the "does status routing account for this" check as an explicit Review Focus line item, not an incidental subagent-review catch.
- Consider a `file <path>` sanity check as a standing habit after any `Edit` call on a large source file, given the NUL-byte incident's detection was accidental.

_Created: 2026-07-16. PRs #106, #107, #108, #109 merged to main via closeout-stack; advisory observations triaged the same day._
