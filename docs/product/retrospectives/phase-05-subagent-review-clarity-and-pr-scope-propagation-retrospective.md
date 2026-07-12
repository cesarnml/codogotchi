# Phase 05 — Subagent Review Clarity and PR Scope Propagation Retrospective

## Scope delivered

Phase 05 shipped four stacked PRs. `P5.01` clarified subagent review guidance in [PR #14](https://github.com/cesarnml/son-of-anton/pull/14). `P5.02` made canonical templates the explicit planning and decomposition source in [PR #15](https://github.com/cesarnml/son-of-anton/pull/15). `P5.03` fixed orchestrator PR title metadata propagation in [PR #16](https://github.com/cesarnml/son-of-anton/pull/16), including the follow-up patch that makes Conventional Commit type and scope come from ticket metadata instead of filename inference. `P5.04` records phase exit state and this retrospective on branch `agents/p5-04-phase-exit-and-retrospective-scaffolding`.

## What went well

The guidance tickets worked because they changed the surfaces agents actually read during delivery: repo instructions, `/soa` skill text, the execution ethos, and the delivery orchestrator document. That kept the fix aligned with the failure mode: mis-execution came from ambiguous operator guidance, not missing runtime enforcement.

The P5.03 patch improved the original scope fix without widening the design. Once ticket decomposition owned canonical `Type:` and `Scope:` metadata, using filenames as a secondary Conventional Commit source became unnecessary drift. Moving both fields through `TicketDefinition` and `TicketState` kept PR title generation simple and inspectable.

## Pain points

The P5.04 ticket carried stale closeout wording that said prior PRs should be merged before the ticket starts. That is avoidable process friction: the stack workflow intentionally keeps PRs open until developer-approved closeout, so phase-exit docs need to distinguish "ticket stack complete" from "merged to main."

External review still treats vendor account-limit comments as review detections. P5.03 had no code findings, but CodeRabbit and Qodo service-limit messages pushed the ticket into `needs_patch` until a clean outcome was recorded manually. This is avoidable triage noise and has now appeared in consecutive phases.

## Surprises

The original P5.03 plan assumed only `Scope:` propagation was missing and that `buildPullRequestTitle` was already correct. The live patch request exposed a second inconsistency: the function still inferred Conventional Commit type from `ticket-NN-<type>-...` filenames. That made sense when Phase 01 introduced the title format, but it was stale after the template began generating required `Type:` metadata.

The PR body refresh after P5.03 recorded the clean review correctly even though the review artifacts included vendor service-limit comments. That preserved evidence while allowing the stack to advance, which is the right operational behavior until vendor-status filtering is hardened.

## What we'd do differently

When ticket metadata becomes canonical, update all older references in the same pass. The original reasoning behind filename type inference was valid for early ticket files, but once decomposition started producing `Type:` and `Scope:` fields, the fallback created a second source of truth.

Phase-exit tickets should say "stack complete, closeout pending" unless the phase uses a non-stacked merge model. The old wording tried to make exit verification concrete, but it contradicted the documented closeout gate.

## Net assessment

Phase 05 achieved its stated goal. The operator guidance now gives agents a clearer execution sequence and subagent-review stance, planning/decomposition docs point at canonical templates, and orchestrator PR titles now use canonical ticket metadata for both Conventional Commit type and scope. The remaining gap is enforcement: this phase deliberately chose guidance-first, and the retrospective evidence supports a follow-up hardening pass for vendor-noise triage and metadata contract validation.

## Follow-up

- Teach AI review triage to classify known CodeRabbit/Qodo rate-limit and account-limit notices as non-actionable vendor status before they create `needs_patch` state.
- Add validation that decomposed tickets include a conventional-commit-compliant `Type:` and, when present, `Scope:`.
- Update phase-exit ticket templates to distinguish completed stacked delivery from developer-approved closeout/merge.

_Created: 2026-05-09. PRs #14, #15, and #16 open; P5.04 PR pending._
