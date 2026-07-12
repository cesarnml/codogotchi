# Phase 14 — Subagent-review classification and outcome fidelity

## Scope delivered

Phase 14 shipped six stacked PRs on the subagent-review fidelity path: ledger schema and identity ([PR #50](https://github.com/cesarnml/son-of-anton/pull/50)), runner selection and codex-cli classification ([PR #51](https://github.com/cesarnml/son-of-anton/pull/51)), outcome derivation and PR-open reconciliation ([PR #52](https://github.com/cesarnml/son-of-anton/pull/52)), artifact triplet rename ([PR #53](https://github.com/cesarnml/son-of-anton/pull/53)), stderr discipline and trace log ([PR #54](https://github.com/cesarnml/son-of-anton/pull/54)), and docs/skills/template alignment plus this retrospective (P14.06, PR pending at closeout).

Delivered contract surfaces: append-only `*-subagent-review.ledger.json` with `primaryAgent`, `runnerSelfReport`, `fallbackFrom`, and `schemaVersion`; operator-explicit `--subagent` / `subagentRunner`; `clean | patched | deferred | skipped` outcomes; `reconcile-subagent-review` silent-lie prevention; `prompt → report → ledger` filenames; adversarial prompt prologue reorder; gitignored `trace.log` for runner stderr.

## What went well

**Ticket slicing matched failure modes.** Each audit failure mode got its own ticket (classification, outcomes/reconciliation, naming, stderr, docs). That kept Red tests focused and made review scope legible — a reviewer could trust P14.03 was only about reconciliation without re-litigating codex exit codes.

**Reconciliation as a named step.** Making `reconcile-subagent-review` invokable separately from `open-pr` gives operators a diagnostic command before publish. Embedding the same gate inside `open-pr` preserves the hard-block without forcing a second mental model.

**Clean-cutover rename discipline.** P14.04's stop condition ("any old triplet name left → pause") forced a repo-wide grep culture that paid off in P14.06: agent-facing paths were already clean before the final docs sweep.

## Pain points

**Codex availability still dominates honest `skipped` rows.** P14.02 fixed misclassification when codex-cli actually runs, but several tickets in this phase still recorded `skipped` when the runner was unavailable or advisory-violation fired. That is honest labeling, not the old bogus `sandbox_denied` on completed reviews — but it means the ledger alone still cannot distinguish "model never ran" from "model ran and found nothing actionable" without reading `terminatedReason`.

**Gated mode tax on a six-ticket stack.** `ticketBoundaryMode: gated` was intentional for operator review, but it multiplied context resets. The resume prompt worked; the cost was elapsed wall time, not confusion.

**Doc-only closing ticket carries the retrospective burden.** P14.06 is the only ticket where prose quality is the product. That is appropriate, but it concentrates audit-comparison honesty into one PR instead of spreading it across code tickets.

## Surprises

**P14.02 subagent review recorded `skipped` on the classification ticket itself.** Irony aside, it validated the "honest skip" path: when neither CLI runner is available in the delivery environment, the ledger says so instead of fabricating `clean`.

**Stderr stripping did not remove forensic value.** Moving stderr to gitignored `trace.log` preserved the audit's rare-debug use case without stuffing 2000-line blobs into the committed report — exactly what the codogotchi audit predicted operators would need.

**Historical delivery docs still mention `--preferred-runner`.** Ticket files and older phase retrospectives under `docs/product/delivery/` intentionally retain Phase 13 wording as delivery archaeology. P14.06's grep stop condition applies to consumer-discoverable surfaces (template, skills, README, orchestrator doc), not frozen ticket narratives.

## What we'd do differently

**Run one end-to-end codex-cli + reconciliation demo on main before calling Phase 14 done.** The phase exit condition describes a fresh ticket demonstrating the full path; this stack delivered the machinery ticket-by-ticket but did not run a single greenfield demo commit on `main` after P14.05. Hindsight: add a one-line "demo ticket" checklist item to the implementation plan's closeout section.

**Consider `subagentRunner` in the repo's own `orchestrator.config.json` for dogfooding.** The no-silent-default contract is correct for consumer repos, but Son-of-Anton maintainers hit the hard error on every resume until they pass `--subagent`. A documented maintainer-only config snippet in README would reduce friction without weakening the consumer default.

## Net assessment

The phase achieved its stated goal relative to the codogotchi P2 audit. The primary failure mode — codex runs that completed but were stamped `skipped` with fabricated `terminatedReason` — is addressed by trusting model self-report in classification and by refusing `clean` when termination is not `completed`. The secondary failure mode — `clean` rows alongside `[subagent-review]` patch commits — is addressed by reconciliation and explicit `patched` / `deferred` vocabulary. A reader can now open `*-subagent-review.ledger.json` and learn what happened without reading report prose first, modulo honest `skipped` when no runner ran. The adversarial prompt prologue reorder closes the "buried escape valve" finding from the audit.

## Follow-up

- After P14.06 merges, run `bun run closeout-stack --plan docs/product/delivery/phase-14/implementation-plan.md` with developer approval.
- Add a maintainer quick-start line to README: example `orchestrator.config.json` with `subagentRunner` for repos that always use one CLI family.
- On the next consumer `/soa update`, spot-check one repo for stale `codex-exec` or old triplet paths outside the subtree (P14.04 deferral assumed clean checkpoints only).

_Created: 2026-05-22. [PR #55](https://github.com/cesarnml/son-of-anton/pull/55) open._
