# Phase 12: Gate placement refactor

**Delivery status:** Product plan drafted, awaiting developer approval. Update when decomposition starts or completes so this line matches repo reality.

## TL;DR

**Goal:** Reorder the orchestrator's TDD gate so `post-red` enforces a real `[red]` commit _before_ implementation runs, not after — eliminating the six-tickets-per-phase friction tax where operators lie to the gate to satisfy a state machine that demands red after green is already committed.

**Ships:**

- `post-red` gate moves to immediately after the `[red]` commit and before `implement + verify` in the documented critical order.
- Ticket metadata gains a single new field, `Red:` (`required` default | `skip`), declared at decomposition time, parsed by the orchestrator, honored as the source of truth for whether the gate runs.
- The gate is _hard_. Soft enforcement is what produced the lie; we are not reintroducing it.
- `--red-commit-sha <sha>` recovery flag is **deleted.** The two honest paths (`Red: skip`, or normal `[red]` → `[green]` pair) cover every legitimate case; the flag's only remaining use was inviting the lie.
- `delivery-orchestrator.md`, `start-here.md`, `docs/template/stubs/ticket.template.md`, and `son-of-anton-ethos` updated together to reflect the new critical order and the `Red:` field.

**Defers:**

- Single-commit TDD support (originally listed as N9 in the synthesis doc) — **not shipped.** The reorder makes the single-commit case impossible under protocol-following work: by the time an agent has implementation to commit, they've already passed `post-red`, which means they've already committed `[red]` separately. The case only arises through off-protocol behavior, and the correct response to off-protocol is "follow the protocol," not "add an escape hatch." If real evidence emerges in a downstream consumer phase that single-commit work has a legitimate non-recovery use case, revisit then with the data.
- Filesystem-hygiene fixes (review JSON Biome reformat, worktree refresh on `advance`), baseline-policy persistence, and small CLI fixes (`subagent-review` positional-arg parsing, `poll-review` "Review skipped" detection) — all phase-13.
- Structured triage `findingDecisions` schema and template Rev 13 — future phase.
- Cross-ticket Rationale-encoded forward dependencies, operator-intent vs runtime-evidence consistency lint, `.env` propagation into running worktrees — N-tier items, not blocking.
- Any rewrite or annotation of pre-phase-12 `state.json` entries that record the `--red-commit-sha HEAD` lie. Past records are the historical record; phase-12 makes future records honest, not retroactively clean.

---

This phase exists because the consuming-repo retrospective for codogotchi phase-01 (`notes/private/codogotchi-phase-01-son-of-anton-retrospective.md`, §4 and App 4 §3) documented six tickets in 21 that paid the post-red-after-implementation tax. Five tickets (P1.01, P1.02, P1.06, P1.08, P1.20) used `--red-commit-sha $(git rev-parse HEAD)` — the green commit lied into the red slot, persisted into `state.json`. P1.16 went further: `git reset --soft HEAD~1` → wrote a stub that throws "not implemented" → committed `test+stub` as `[red]` → ran `post-red` → restored the real implementation → committed `[green]`. The retro's own assessment of that pattern: _"strictly worse than the `--red-commit-sha HEAD` lie."_ The orchestrator now believes red was real; nothing in the audit trail tells the next reader the split was synthetic.

The diagnosis from §4 of the source synthesis is that the current order biases agents toward sloppy work by structure: an agent who implements until green naturally arrives at `post-red` _after the fact_ and reaches for the recovery flag. Phase-12 reorders the gate so the discipline check sits _in front of_ implementation. The agent encounters the red requirement before writing impl. Split-commit TDD becomes the only path because the structural ordering enforces it. There is no single-commit escape hatch; if the agent goes off-protocol and implements without a `[red]` commit, the gate refuses and the recovery is to follow the protocol — `git reset --soft HEAD~1`, commit `[red]` and `[green]` properly.

This phase is deliberately small. The synthesis doc originally bundled an N9 single-commit TDD convention with diff-based red verification. That convention solved a problem the reorder itself eliminates by construction — under the new order, a protocol-following agent cannot land in the single-commit case. Shipping the convention anyway would resurrect the attractive-nuisance properties of `--red-commit-sha <sha>` under a new name. So phase-12's scope tightens to M7 plus the metadata-field and docs work it requires. Nothing else.

## Phase Goal

This phase should leave the product in a state where:

- The documented critical order in `delivery-orchestrator.md` and `start-here.md` reads: `start → write failing test → commit [red] → post-red → implement + verify → post-verify → subagent-review → open-pr → poll-review → record-review → advance`. The `post-red` gate sits between the `[red]` commit and the implementation step. Future readers see the discipline check in front of the work, not behind it.
- Ticket docs authored after phase-12 carry a `Red:` field in their top-level metadata block alongside the existing `Size:`, `Type:`, and `Scope:` fields. Values: `required` (default) | `skip`. The orchestrator reads this at `start`, lifts the value, and either runs or skips the `post-red` gate accordingly. The truth lives in the ticket doc — visible to any future reader without state.json archaeology.
- The `post-red` gate is hard. `Red: required` with no `[red]` commit at HEAD refuses to advance. The error message names the two honest recovery paths: author a `[red]` commit before continuing, or revise the ticket metadata to `Red: skip` if the ticket genuinely has no testable behavior.
- The `--red-commit-sha <sha>` flag is deleted. Its three former use cases collapse to two honest paths absorbed by the new gate behavior and the `Red:` field.

## Committed Scope

Two surfaces of work, in service of the same goal. Cross-references in brackets cite the patch IDs from `notes/private/phase-11-soa-patch-plan-from-codogotchi-p1-retro.md` so decomposition can pull straight through.

### Orchestrator gate ordering

- Move `post-red` to immediately after the `[red]` commit and before `implement + verify` in the documented critical order. `start-here.md`, `delivery-orchestrator.md`, and any state-machine diagrams update together. [M7]
- Delete the `--red-commit-sha <sha>` flag. Remove from CLI parsing, error text, and documentation. Its absorption by `Red: skip` plus the natural `[red]` → `[green]` flow is complete; the flag's continued existence is an attractive nuisance.
- When `post-red` refuses to advance, error text enumerates the two honest paths: author a `[red]` commit before continuing, or revise the ticket metadata to `Red: skip` if the ticket genuinely has no testable behavior.

### Ticket metadata and decomposition contract

- Add `Red:` to the canonical ticket metadata block in `docs/template/stubs/ticket.template.md`. Values: `required` (default) | `skip`. Field sits alongside `Size:`, `Type:`, and `Scope:` — the same shape that has held across every phase to date without drift.
- Orchestrator parses the field strictly. Missing `Red:` defaults to `required`. Unrecognized values produce an explicit error naming the two expected literals.
- Update `son-of-anton-ethos` and any other agent-facing skill text that encodes the old gate ordering, so agents executing phases pick up the new flow without rereading `delivery-orchestrator.md` from scratch.

### Operator contract update

- `/soa update` precondition: consumers close out their current phase before updating. Phase-12 ships against a known starting state. No migration command, no state.json rewrite, no forced re-start. Document this contract in `delivery-orchestrator.md` and the update flow.

## Explicit Deferrals

- **Single-commit TDD support (synthesis N9).** Not shipped. The reorder eliminates the case under protocol-following work. Shipping a `TDD: single-commit` field or diff-revert verification would resurrect the attractive-nuisance properties of `--red-commit-sha <sha>`. Revisit only if a consumer phase produces hard evidence of a legitimate non-recovery use case.
- **Phase-13 hygiene work** — review JSON Biome reformat (M9), worktree filesystem refresh on `advance` (M14), `subagent-review` positional-arg parsing (M12), `poll-review` "Review skipped" body-text detection (M13). All are real friction items, none touch gate ordering. They ride together in phase-13.
- **Baseline-policy persistence and resume-prompt flag rendering** (M10, M11) — phase-13. Independent of the gate apparatus.
- **Structured triage `findingDecisions` schema** — future phase. Replacement of the free-text triage `note` field with structured `{threadId, decision, rationale}` triples. Independent of gate ordering.
- **Template Rev 13** (push-back rationale must name the spec clause) — pairs with the structured triage schema; ships when that does.
- **`verify-red` standalone CLI subcommand** — explicitly _not_ shipped. The verification work belongs _inside_ `post-red`; it is not a new top-level command.
- **State.json archaeology / migration tooling** — past records are the historical record. Phase-12 makes future records honest. Retroactive cleanup contradicts the audit-trail principle motivating the phase.
- **Re-litigating the adversarial review template** — phase-11 just shipped that work. Phase-12 does not reopen it.
- **Changes to how `[red]` commits are _authored_** (commit hooks, lint rules, auto-prefix tooling) — phase-12 is about _gate ordering_; commit authoring is unchanged.
- **Cross-ticket Rationale-encoded forward-dependency tooling, operator-intent vs runtime-evidence consistency lint, mid-phase `.env` propagation, `chore(delivery)` commit-title disambiguation, followups-tracking artifact** — N-tier items cataloged in the synthesis artifact. None block phase-12's goal.

## Exit Condition

When phase-12 is done, the following are demonstrably true:

- `docs/template/delivery/delivery-orchestrator.md` and `docs/template/overview/start-here.md` document the new critical order with `post-red` immediately after the `[red]` commit and before `implement + verify`. Any state-machine diagrams in those documents match the new order.
- `docs/template/stubs/ticket.template.md` declares the `Red:` field (with `required` default and `skip` alternative) in the top-level metadata block, alongside `Size:`, `Type:`, and `Scope:`.
- The orchestrator code (`tools/delivery/...`) parses the `Red:` field, enforces the gate hard for `Red: required`, skips the gate for `Red: skip`, defaults to `required` when absent, and produces error text that names the two honest paths when `post-red` refuses to advance.
- The `--red-commit-sha <sha>` flag is removed from CLI parsing, error text, and all documentation. Searches across the repo for its name return zero results outside this plan and the retro that motivated its removal.
- `son-of-anton-ethos` and any other agent-facing skill text reflects the new ordering and the `Red:` field.
- `bun run ci` is green. Spellcheck includes any new terminology introduced by the metadata field.
- A retrospective lands at `docs/product/retrospectives/phase-12-gate-placement-refactor-retrospective.md` documenting the prediction (six-tickets-per-phase tax eliminated) and the friction points encountered while SoA delivered phase-12 through phase-12's own state machine.

Validation that operators actually find the new path frictionless happens organically in the next consumer phase. Phase-12 closes on repo-level deliverables.

## Retrospective

`required` — phase-12 changes the orchestrator's documented critical order (operator workflow change), introduces a new ticket-metadata field that consumers must adopt (durable boundary), deletes a previously-supported CLI flag (durable boundary), and underwrites every future phase with a stable gate-ordering contract (later-phase assumption). The retrospective is written at phase-12 closeout against the SoA-repo-level deliverables; downstream validation of the friction-elimination claim happens organically in consuming repos.

---

## Risk envelope

One risk worth naming at plan time. Earlier drafts named more; the others collapsed under scrutiny — either they were anticipated-friction the design already addresses or self-correcting under the new gate's natural feedback.

1. **SoA-delivering-itself recursion.** Phase-12 ships gate-ordering and metadata-parsing changes through the very state machine they modify. A mid-phase bug in the parser, the gate placement logic, or the error-text wiring lands in in-flight tickets before it can be reverted. Mitigation: sequence the contract work (`Red:` field parser, defaults, error messages) to land and stabilize before the behavior change (gate placement move). Same pattern phase-11 used for the artifact schema → runner contract sequencing. Decompose-time concern to encode in ticket order.

Risks considered and intentionally not included:

- **Decomposition agent mislabels `Red: skip` on a `feat` ticket** — caught at the developer-review checkpoint in `/soa decompose`. The control surface (human review at decomposition gate) already exists.
- **Implementing agent goes off-protocol and implements without a `[red]` commit** — the structural reordering of `post-red` to before implementation is itself the mitigation. The gate refuses to advance; the recovery is to follow the protocol (`git reset --soft HEAD~1`, commit `[red]` and `[green]` properly). Not a risk; the gate working correctly.
- **Backward compatibility for tickets authored before phase-12** — handled by the default (`Red: required` if absent) and by the `/soa update` precondition that consumers close before updating. No flag-day, no migration.
- **Tiny tickets feel artificial to split into `[red]` and `[green]`** — the discipline cost is ~30 seconds per ticket and produces a cleaner audit trail. Not a risk; the cost-benefit clearly favors the split.
