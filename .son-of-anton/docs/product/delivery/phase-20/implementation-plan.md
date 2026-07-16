# Phase 20 — Subagent Refactor Review

> Adds a dedicated pre-PR cold-read subagent gate for the Refactor leg of TDD, analogous to the existing adversarial `subagent-review` gate but scoped to local quality signals (duplication, naming, dead code, complexity, test-name/behavior alignment) instead of correctness/attack-surface hunting.

## Epic

Originates from issue #76. Design stance pre-agreed in `notes/public/refactor-advisory-subagent-design.md` (`Status: DECIDED` prior to this phase; flipped to `Status: IMPLEMENTED` on completion).

## Product contract

Once shipped, a developer can set `reviewPolicy.refactorReview: "runner_on_red"` in `orchestrator.config.json` and a `Red: required` ticket will not reach `open-pr` without a cold-read subagent pass over the Refactor leg — a second pair of eyes distinct from the primary agent's own `post-verify` self-audit and distinct from the existing correctness-focused adversarial gate. Deferred suggestions surface again at the next `advance`, so they aren't silently lost.

## Grill-Me decisions locked

- **Policy scope this phase:** only `disabled` | `runner_on_red`. `runner_on_red_strict` (fail-closed `open-pr` enforcement) is explicitly deferred — named in docs as a future value, not implemented or wired into any guard.
- **Deferred-suggestion surfacing:** ledger record (`reviews/<ticket>-refactor-review.ledger.json`) plus a print in the next `advance` output. No automated follow-up ticket creation, no `/soa tao` integration — that lane's post-phase-closeout timing is structurally wrong for refactor-suggestion staleness, and its parser is scoped to a different tag.
- **No metrics/reporting tooling.** Ledger JSON stays ad-hoc queryable (`jq`/`grep`) if strict-mode rollout is considered later.
- **Rollout: disabled everywhere at ship time**, including this repo's own `orchestrator.config.json` and the consumer `/soa update` sync path. No migration force-writes `runner_on_red` anywhere. The developer flips it on manually, per repo, when ready to pilot.
- **Report parser:** the `<refactor-suggestions>` tagged-block contract (per `notes/public/subagent-report-parser-contract.md`) is built fresh for this new artifact type. The existing adversarial gate's heading-based parser (`extractReportSection`, `CANONICAL_REPORT_SECTION_HEADINGS` in `reconciliation.ts`) is explicitly **not** touched or migrated this phase — that is separate, already-decided-but-unbuilt work outside this phase's approved scope.
- **Architecture:** the refactor gate's three commands reuse the existing generic runner core in `subagent-runner.ts` (`tryRunner`, `runSubagentWithFallback`, `buildRunnerArtifact`, fallback-order/rate-limit logic — none of it adversarial-specific) parameterized by a `kind` value, rather than duplicating that machinery. New `case` blocks are added to `cli-runner.ts`; new state fields are added to `types.ts`.
- **Ticket sequencing:** standard linear stack (20.01 → 20.02 → 20.03 → 20.04), each branching off the previous. No decoupled/parallel tickets — SoA only supports linear stacks.
- **Retrospective:** required (durable operator-workflow boundary change; deferred decisions — strict-mode timing, whether advance-time surfacing proves sufficient — need a forcing function to revisit with real usage data).

## Ticket Order

1. `P20.01 Config, types, template, refactor-suggestions parser & reconciliation`
2. `P20.02 Refactor-review CLI commands`
3. `P20.03 Gate placement, guards & core docs`
4. `P20.04 Advance-time surfacing & remaining docs`

## Ticket Files

- `ticket-01-config-types-parser-reconciliation.md`
- `ticket-02-refactor-review-cli-commands.md`
- `ticket-03-gate-placement-guards-core-docs.md`
- `ticket-04-advance-surfacing-remaining-docs.md`

## Exit Condition

A `Red: required` ticket run against this repo's own delivery, with `refactorReview` manually flipped to `runner_on_red` in `orchestrator.config.json`, demonstrably cannot reach `open-pr` without `write-subagent-refactor-review` → `subagent-refactor-review --subagent <runner>` → `reconcile-subagent-refactor-review` completing in order, after `post-verify` and before the adversarial gate. The resulting `reviews/<ticket>-refactor-review.*` artifacts exist with adjudicated ledger rows (`id`/`summary`/`decision`/`reason`). A deferred row (if any) is visible in the next `advance`'s output. The adversarial gate runs afterward unaffected — its parser and report contract are untouched. `orchestrator.config.json` in this repo and the consumer update path both still read `disabled` unless a developer has manually changed them. `notes/public/refactor-advisory-subagent-design.md` reads `Status: IMPLEMENTED`.

## CI Baseline

> Baseline recorded: 2026-07-16 — to be captured by ticket 20.01 on branch start (`bun run ci:quiet` on `main` before first ticket work begins).

## Review Rules

- Tickets must be merged in order: 20.01 → 20.02 → 20.03 → 20.04.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Tickets 20.01–20.04 are all `Red: required` — none of them qualify for doc-only auto-skip, since each touches `tools/delivery/*.ts` even where most of the diff is documentation (ticket 20.04).

## Explicit Deferrals

- `runner_on_red_strict` policy value and its `open-pr` fail-closed enforcement — not built.
- Automated follow-up ticket creation for deferred refactor suggestions — ledger + advance-time print only.
- Pilot-metrics reporting/dashboard tooling.
- Any auto-enable of `refactorReview` via `/soa update` migration or in this repo's shipped config — ships `disabled` everywhere; manual opt-in only.
- Migrating the adversarial gate's heading-based report parser to the tagged-contract design — separate, already-decided-but-unbuilt work, out of this phase's scope.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- Any temptation to touch the adversarial gate's existing report parser (`reconciliation.ts`'s heading-based extraction) — that is out of scope; stop and flag rather than opportunistically migrating it.
- Any temptation to wire `refactorReview` to a non-`disabled` default in this repo's `orchestrator.config.json` or in the consumer sync/update path — that is an explicit, developer-only manual action, never an automated side effect of this phase's delivery.

## Phase Closeout

Retrospective: required
Why: adds a second mandatory pre-PR subprocess gate to the critical path of every future `Red: required` ticket (in this repo and, once individually opted in, any consumer repo) — a durable operator-workflow boundary change — and carries deferred decisions (strict-mode timing, whether advance-time surfacing proves sufficient) that need a forcing function to revisit with real usage data.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-20-subagent-refactor-review-retrospective.md`
