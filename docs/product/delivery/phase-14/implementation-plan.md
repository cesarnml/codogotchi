# Phase 14 — Subagent-review classification and outcome fidelity

> Make the subagent-review ledger semantically honest: fix codex-cli misclassification, add `patched`/`deferred` outcome states with operator-explicit subagent selection and PR-open reconciliation, rename the artifact triplet, and clean up stderr discipline so the ledger stands alone as a trustworthy audit trail.

## Epic

Follow-on to Phase 13 (adversarial review pipeline honesty). The first full-phase run of Phase 13's pipeline (codogotchi `phase-02`) produced systematically mislabeled ledgers — see `notes/private/2026-05-21-codogotchi-p2-subagent-review-architecture-audit.md` for the motivating evidence.

## Product contract

After Phase 14 ships, a reader can open a `*-subagent-review.ledger.json` file and learn — from the JSON alone, without cross-checking report prose or git log — whether the review ran, whether findings were acted on, and whether anything was consciously deferred. Codex-cli runs that completed are recorded as such (not silently as `skipped`). Subagent selection is operator-explicit at invocation. PR open is hard-blocked when the ledger would silently lie. The artifact triplet reads coherently as `prompt → report → ledger`.

## Grill-Me decisions locked

- **Ticket count** → 6 tickets with clean Red discipline (one type per ticket); rationale: Q1's "5 tickets = 5 scope surfaces" was a useful start, but splitting the closing ticket into pure-behavior (stderr/trace) and pure-docs (prologue/alignment/retrospective) preserves Red-required vs Red-skip cleanliness and matches Phase 13's P13.04 precedent.
- **Red strategy for mixed-type tickets** → `Red: required` with rename riding inside Green; the Red test references new names and naturally drives the rename to happen first.
- **Primary-agent detection** → Operator-explicit, not inferred. `--subagent <claude-cli|codex-cli>` strict-enum flag with `orchestrator.config.json:subagentRunner` project-level default; missing both is a hard error (no SoA-shipped silent default). Optional `--primary <free-form>` flag (with config field `primaryAgent`) records identity in the ledger for retrospective audit; defaults to `"unknown"`. Each ledger row records a single `primaryAgent`; multi-primary scenarios captured naturally across the append-only rows.
- **PR-open reconciliation behavior** → Hard-block on silent-lie conditions; non-zero exit with named resolution paths. `--ack-reconciliation patched|deferred|clean` flag is the escape valve. Composes with headless invocation; impossible to ship a silent lie.
- **Per-ticket exit conditions** → Each ticket's Outcome section lists a green unit test target AND a one-line manual-demo command. Forces falsifiability and produces a demonstrable artifact per ticket.
- **Cross-family review** → Documented best-practice, not enforced mechanism. The operator picks; the ledger records `primaryAgent` and `runnerKind` so cross-family achievement is computable post-hoc.
- **Stderr trace storage** → Local-only, gitignored. Operator-in-the-loop inspection is the v1 audit mechanism; multi-tenant trace persistence is a children-of-anton concern (recorded in `notes/private/children-of-anton-brainstorm.md`).
- **Artifact triplet rename** → Clean cutover, no dual-name fallback. Consumer repos `/soa update` only at clean phase checkpoints.

## Ticket Order

1. `P14.01 Ledger schema vocabulary and identity fields`
2. `P14.02 Runner selection, naming, and classification fidelity`
3. `P14.03 Outcome derivation and PR-open reconciliation`
4. `P14.04 Artifact triplet rename`
5. `P14.05 Stderr discipline and trace log`
6. `P14.06 Prompt prologue reorder, docs/skills/template alignment, phase retrospective`

## Ticket Files

- `ticket-01-ledger-schema-vocabulary-and-identity-fields.md`
- `ticket-02-runner-selection-naming-and-classification-fidelity.md`
- `ticket-03-outcome-derivation-and-pr-open-reconciliation.md`
- `ticket-04-artifact-triplet-rename.md`
- `ticket-05-stderr-discipline-and-trace-log.md`
- `ticket-06-prompt-prologue-reorder-and-docs-alignment.md`

## Exit Condition

A freshly delivered ticket in any consumer repo demonstrates the new fidelity path end-to-end:

- A codex-cli review that completes is recorded as `outcome: clean | patched | deferred` reflecting actual primary action — not `skipped` with a bogus reason.
- A claude-cli review that finds nothing actionable produces a `clean` row; one that prompts a follow-up patch commit produces a `patched` row referencing the commit SHA via auto-detection.
- A pure-defer case produces a `deferred` row with rationale captured via `bun run deliver subagent-review record-deferred --reason "..."`.
- PR-open reconciliation hard-blocks on silent-lie conditions; operator resolves via patch+label, `record-deferred`, or `--ack-reconciliation`.
- Artifact files on disk read `*-subagent-review.{prompt.md, report.md, ledger.json}`; old triplet names are absent from the writer surface.
- The adversarial prompt prologue presents broadening clauses (extra surfaces, human-review bucket) before narrowing clauses (not a general code review).
- The persisted `report.md` contains no stderr blob; `trace.log` exists locally and is gitignored.
- Documentation, skills, and templates describe the same flow.

## CI Baseline

> Baseline recorded: 2026-05-22 — pass (482 tests, 0 failures, 888 `expect()` calls across 39 files; prettier + lint clean). Recorded after spellcheck was removed from CI (`bun run ci:quiet` no longer runs cspell; cspell.json deleted; cspell dev-dep uninstalled).

Recorded on `main` before P14.01 starts via `bun run ci:quiet`. Per-ticket CI diffs against this baseline are unambiguous.

## Review Rules

- Tickets must be merged in order (1 → 6).
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- P14.01's schema is critical-path foundation; slip propagates to all behavior tickets.
- The artifact triplet rename (P14.04) must touch every consumer-repo-discoverable reference; incomplete sweeps trigger the P14.04 stop condition.

## Explicit Deferrals

- **Backward compatibility with the old artifact triplet names.** Consumer repos `/soa update` only at clean checkpoints; no dual-name fallback ships.
- **Migration of historical pre-Phase-14 ledger artifacts.** Pre-Phase-14 ledger rows stay byte-identical to their committed state.
- **Persistence of forensic traces beyond worktree lifetime.** Local-only, gitignored. The operator-in-the-loop inspection model is the v1 audit mechanism.
- **Structured findings parsing.** Report prose remains the canonical findings record; no finding-id → patch-sha mapping.
- **Rubric content changes.** The seven diff-derived classes, three finding-discipline clauses, and required output format are unchanged. Only prologue section order moves.
- **Subagent review runners beyond claude-cli and codex-cli.** v1 supports only these two; gemini-cli, copilot-cli, and other frontier runners are deferred. The `<tool-family>-cli` naming convention is established for future composition.
- **Architecting for "neither claude nor codex available."** At least one assumed installable; both-missing is an install problem.
- **Multi-runner concurrency.** Single-runner with documented fallback; parallel cross-agent review not in scope.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- **P14.02 — Authentic rate-limit signal complexity.** If codex-cli or claude-cli emits multiple distinct rate-limit shapes (soft-throttle separate from hard-limit), or if the rate-limit indicator turns out to be platform-version-dependent, pause for developer input on whether to support all shapes in Phase 14 or defer some to follow-up.
- **P14.03 — Reconciliation edge cases beyond Q4 scenarios.** If reconciliation logic encounters edge cases the product plan or grill scenarios didn't cover (merge commits touching reviewed files, partial squash artifacts mid-stack, post-revert states), pause before shipping a heuristic. Reconciliation is the load-bearing silent-lie-prevention mechanism.
- **P14.04 — Incomplete rename sweep.** If after completing the artifact triplet rename any consumer-repo-discoverable reference to the old triplet names remains in codebase, docs, skills, retrospectives, or `orchestrator.config.json`, pause before merging.
- **P14.06 — Doc-skill drift surfaces beyond enumerated scope.** If updating one skill or doc reveals that another references the old contract in a way not obvious from the Phase 14 plan, pause to enumerate the full set before mass-editing.

## Phase Closeout

Retrospective: required
Why: Phase 14 changes the durable ledger schema, artifact filename contract, and PR-open reconciliation behavior. All three are operator-workflow surfaces; later phases assume their semantics.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-14-subagent-review-classification-and-outcome-fidelity-retrospective.md`
