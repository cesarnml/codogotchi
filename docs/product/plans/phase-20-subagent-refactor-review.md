# Phase 20: Subagent Refactor Review

**Delivery status:** Product plan — awaiting developer approval. Update this line when decomposition starts or completes.

## TL;DR

**Goal:** Close the structurally-uncovered Refactor leg of Son of Anton's Red → Green → Refactor TDD flow with a dedicated cold-read subagent gate, analogous to the existing adversarial `subagent-review` gate but scoped to local quality signals instead of correctness/attack-surface hunting.

**Ships:**

- New pre-PR gate: `write-subagent-refactor-review` → `subagent-refactor-review --subagent <runner>` → `reconcile-subagent-refactor-review`, placed after `post-verify` and before the adversarial `write-subagent-adversarial-review` step.
- New `refactorReview` policy field in `orchestrator.config.json` with two supported values this phase: `disabled` | `runner_on_red`.
- New artifact triplet per ticket: `reviews/<ticket>-refactor-review.{prompt.md,report.md,ledger.json}`, using a dedicated `<refactor-suggestions>` tagged block (never `<advisory-observations>`).
- Ledger rows adjudicated by the primary agent: `id`, `summary`, `decision` (`accepted`/`rejected`/`deferred`), `reason` (required for reject/defer).
- `advance` prints any newly-deferred refactor-review ledger rows from the completed ticket so a human can act on them at the next natural ticket boundary, instead of only in a post-phase sweep.
- `notes/public/refactor-advisory-subagent-design.md` updated from `Status: PROPOSED` to `Status: IMPLEMENTED`, pointing at this plan.
- Doc updates mirroring the adversarial gate's documentation footprint: `docs/template/delivery/delivery-orchestrator.md`, `docs/template/delivery/tdd-workflow.md`, new `docs/template/delivery/refactor-review-template.md`, `.agents/skills/son-of-anton-ethos/SKILL.md`.

**Defers:**

- `runner_on_red_strict` (fail-closed `open-pr` enforcement) — not built this phase. Named as a future value pending pilot data from `runner_on_red` usage.
- Automated follow-up ticket creation for deferred refactor suggestions — the ledger + advance-time print is the only surfacing mechanism this phase.
- Pilot-metrics reporting tooling (acceptance rate, `[refactor-review]` commit counts, reject/defer ratio) — ledger JSON remains ad-hoc queryable (`jq`/`grep`); no dashboard or report command is built.
- Auto-enabling `refactorReview` anywhere. Ships `disabled` in this repo's own `orchestrator.config.json` and in the consumer sync/update path. No migration force-writes `runner_on_red` for any repo, including this one. The developer flips it on manually, per repo, when ready to pilot.

---

`post-verify` catches issues, but it is the same actor that wrote the code reviewing its own diff — authorship bias is structural, not a matter of instruction quality. The existing adversarial `subagent-review` gate already solved this for correctness by inserting a cold reader with an adversarial brief before `open-pr`. The Refactor leg of TDD has no equivalent: it is nominally present in doctrine but has no second pair of eyes. Issue #76 and the prior design stance note (`notes/public/refactor-advisory-subagent-design.md`, already `Status: DECIDED`) converged on mirroring the adversarial pattern exactly, with a distinct non-adversarial brief (duplication, naming, dead code, complexity, test-name/behavior alignment — not architecture, not invariants).

## Phase Goal

This phase should leave the product in a state where:

- A `Red: required` ticket, when `refactorReview` is set to `runner_on_red` in `orchestrator.config.json`, cannot reach `open-pr` without the primary agent having run `write-subagent-refactor-review` → `subagent-refactor-review --subagent <runner>` → `reconcile-subagent-refactor-review`, in that order, after `post-verify` and before the adversarial gate.
- The refactor runner's report is parsed via the same tagged-contract mechanism the adversarial report already uses (per `notes/public/subagent-report-parser-contract.md`), under its own `<refactor-suggestions>` tag — never colliding with `<advisory-observations>`.
- Every refactor suggestion is adjudicated by the primary agent with a per-item reason recorded in the ledger; the primary may reject all of them and still complete the gate.
- `advance` surfaces any `deferred` refactor-review rows from the ticket just completed, so a human sees them at the next ticket boundary rather than only during a phase-end sweep.
- `refactorReview` defaults to `disabled` everywhere — this repo's checked-in config and every consumer repo's post-update config — until a developer explicitly opts in.
- `notes/public/refactor-advisory-subagent-design.md` reads `Status: IMPLEMENTED` and points at this phase.

## Committed Scope

### Gate mechanics

- Three new orchestrator commands mirroring the adversarial triplet: `write-subagent-refactor-review`, `subagent-refactor-review --subagent <runner>`, `reconcile-subagent-refactor-review`.
- Gate placement: `post-verify` → refactor gate (three steps) → adversarial gate (existing three steps) → `open-pr`.
- Applies only to code tickets declaring `Red: required`; `Red: skip` and doc-only tickets bypass structurally, same as the adversarial gate's doc-only bypass shape.
- Runner selection, fallback order, and the advisory-only contract (no worktree writes; a detected write flips the outcome to `skipped`/`advisory_violation`) mirror `subagent-review`'s existing behavior exactly — this is inherited mechanics, not a new design surface.

### Policy

- `reviewPolicy.refactorReview` (or a top-level `refactorReview` field, matching wherever `subagentReview`/`prReview` currently live in config shape) accepts `disabled` | `runner_on_red` this phase.
- `runner_on_red`: on `Red: required` tickets, the runner must be invoked and a ledger produced; the primary may reject every suggestion. No `open-pr` hard-block if the artifact is somehow missing (soft enforcement, matching the design note's description).
- Default (absent key, and this repo's committed config at ship time): `disabled`.

### Artifacts and brief

- `reviews/<ticket>-refactor-review.prompt.md` — primary-authored, filled from a new `refactor-review-template.md`.
- `reviews/<ticket>-refactor-review.report.md` — runner prose, with a `<refactor-suggestions>` / `None` tagged block per the existing report-parser contract.
- `reviews/<ticket>-refactor-review.ledger.json` — `SubagentRunnerArtifact`-shaped, plus adjudication rows (`id`, `summary`, `decision`, `reason`).
- Brief scope, explicitly bounded to local quality signals: duplication introduced by the implementation, naming that didn't survive Green, dead code/scaffolding, flattenable complexity now that the shape is known, test names misaligned with behavior. Explicitly not in scope for the runner: architectural rewrites, invariant/attack-surface hunting (that stays the adversarial gate's job).
- Each suggestion in the report must state a behavior-preservation assertion and name which tests still cover the refactored code — a prompt-level requirement, enforced by template + primary review, not by the parser.

### Advance-time surfacing

- `advance` reads the just-completed ticket's refactor-review ledger and prints any `deferred` rows to the console/handoff output. This reuses `advance`'s existing per-ticket-boundary execution point; it is not a new sweep mechanism and does not touch `/soa tao`.

### Documentation

- `docs/template/delivery/delivery-orchestrator.md` — new section mirroring "Subagent adversarial review (ticket stacks)," placed before that section per gate order; `Critical Step Order` list updated; `Commands` table updated.
- `docs/template/delivery/tdd-workflow.md` — Refactor leg updated to describe the gate instead of describing it as agent discretion.
- `docs/template/delivery/refactor-review-template.md` — new file, brief + copy-me `<refactor-suggestions>` tag skeleton.
- `.agents/skills/son-of-anton-ethos/SKILL.md` — execution-mechanics update so the ethos skill drives the new gate in its stop-condition/step sequencing, same as it already does for the adversarial gate.
- `notes/public/refactor-advisory-subagent-design.md` — `Status: PROPOSED` → `Status: IMPLEMENTED`, with a pointer to this plan.
- `README.md` / `docs/template/overview/start-here.md` — updated only if the exact command sequence shown there needs the new steps inserted (decompose will confirm exact touch points).

## Explicit Deferrals

- **`runner_on_red_strict`** — fail-closed `open-pr` enforcement when the refactor-review artifact is missing. Deferred pending real usage data from `runner_on_red`; the config value is not implemented this phase (may be named in docs as a future value, not wired into any guard).
- **Automated follow-up ticket creation for deferred suggestions** — rejected as a mechanism this phase. The ledger record plus advance-time console print is the only surfacing; no ticket-system integration.
- **Pilot-metrics tooling** — no report/dashboard command. The four candidate metrics named in the design note (acceptance rate, `[refactor-review]` commit count, regressions, reject/defer ratio) remain manually queryable from committed ledger JSON via `jq`/`grep` if/when strict-mode rollout is being considered later.
- **Auto-enabling `refactorReview` via `/soa update` migration** — explicitly rejected for this phase, reversing an earlier draft of this plan. Both this repo's own `orchestrator.config.json` and the consumer sync/migration path ship with `refactorReview` absent or explicitly `disabled`. No repo — including this one — gets the gate turned on as a side effect of this phase landing or of running `/soa update`. The developer enables it manually, per repo, when ready to pilot.
- **`/soa tao` (triage-advisory-observations) integration** — explicitly rejected. That lane's post-phase-closeout timing is structurally wrong for refactor-suggestion staleness (a suggestion from ticket 3 may be moot by ticket 12), and its parser is scoped to the `<advisory-observations>` tag by design; reusing it would either pollute that lane or require a second parser path bolted onto a mistimed sweep.

## Exit Condition

A `Red: required` ticket run against this repo's own delivery, with `refactorReview` manually flipped to `runner_on_red` in `orchestrator.config.json`, demonstrably cannot reach `open-pr` without the three refactor-review steps completing in order; the resulting `reviews/<ticket>-refactor-review.*` artifacts exist with adjudicated ledger rows; a deferred row (if any) is visible in the next `advance`'s output; and the same ticket's adversarial gate runs afterward unaffected. `orchestrator.config.json` in this repo and the consumer update path both still read `disabled` unless a developer has manually changed them. The design note reads `Status: IMPLEMENTED`.

## Retrospective

`required` — this phase adds a second mandatory pre-PR subprocess gate to the critical path of every future `Red: required` ticket (in this repo and, once individually opted in, any consumer repo), which is a durable operator-workflow boundary change, and it carries deferred decisions (strict-mode timing, whether advance-time surfacing proves sufficient) that need a forcing function to revisit with real usage data.
