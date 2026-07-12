# Phase 14: Subagent-review classification and outcome fidelity

**Delivery status:** Decomposed into 6 tickets at `docs/product/delivery/phase-14/`; ready for execution. Update this line when execution starts and again when the phase ships.

## TL;DR

**Goal:** Make the subagent-review ledger reflect what actually happened — fix the codex-exec exit-code misclassification, introduce real `patched`/`deferred` outcome states, and clean up artifact naming and stderr discipline — so a reader can trust the ledger without cross-checking the report prose.

**Ships:**

- The `codex-exec` runnerKind is renamed to `codex-cli`, standardizing on the `<tool-family>-cli` convention so future runners (gemini-cli, copilot-cli, etc.) compose naturally with the same shape.
- Codex-cli runner classification trusts the model's self-reported `runnerStatus: completed` trailer over external sandbox/rate-limit heuristics, so codex-cli runs that actually completed stop being mislabeled as `skipped`.
- Subagent selection is operator-explicit. `/soa execute` and `/soa resume` accept `--subagent <claude-cli|codex-cli>` as a strict enum. A project-level default lives in `orchestrator.config.json:subagentRunner` so habitual choices don't require the flag on every invocation. Precedence: flag > config field > hard error. The orchestrator ships no built-in silent default; the operator must declare somewhere.
- An optional `--primary <kind>` flag (with project-level default in `orchestrator.config.json:primaryAgent`) records primary-agent identity in the ledger for retrospective audit. The flag accepts free-form values — `claude`, `codex`, `cursor`, `composer`, `copilot`, `aider`, etc. — because `--primary` is information-only and does not drive orchestrator behavior. Defaults to `"unknown"` if neither flag nor config is set. The `-cli` suffix is reserved for `--subagent` (signaling a headless-invocable runner with a known contract); `--primary` values omit it.
- Each ledger row records a single `primaryAgent` value reflecting what was true at that invocation. Multi-primary scenarios (e.g., operator starts a ticket under claude, hits rate-limit, resumes under codex) are naturally captured across multiple rows in the append-only ledger; no array-per-row is needed.
- Cross-family review is documented best-practice in the `--subagent` help text and the `soa` skill, not an orchestrator-enforced default. The operator chooses; the ledger records both `primaryAgent` (when set) and `runnerKind` so cross-family-achievement is computable post-hoc without consulting thread context.
- When the operator-specified subagent fails the availability predicate, the fallback chain selects the other configured runner and records `fallbackFrom: <originally-requested-kind>` on the row. Same-family-by-fallback is distinguishable from same-family-by-choice in the ledger.
- "Runner availability" is sharpened to a dynamic predicate. A runner is unavailable when its binary is missing, its invocation errors, it returns a rate-limit signal, it has a network failure, or it fails to process the prompt. Any of those triggers fallback to the next runner in the chain; `skipped` is recorded only when all configured runners genuinely fail availability.
- Ledger schema gains `patched` and `deferred` outcome states alongside `clean | skipped`, and a `schemaVersion` field so future additions don't break consumers.
- Auto-detection of `[subagent-review]`-labeled commits between `reviewedHeadSha` and the open-pr step writes a `patched` ledger row automatically; a new CLI affordance `record-deferred` writes a `deferred` row with rationale for the pure-defer case.
- A PR-open reconciliation prompt blocks PR open when reviewed files were modified without a `[subagent-review]` commit, or when actionable findings exist with no acknowledgment, so the ledger cannot silently lie as `clean`.
- Artifact triplet renamed to `*-subagent-review.{prompt.md, report.md, ledger.json}` — replacing the obtuse `runner.json` / `review-outcome.md` / `adversarial-prompt.md` names that describe the mechanism rather than the slot.
- Adversarial prompt prologue reordered to promote the "you may add extra surfaces" and "Findings for human review" escape valves above the "not a general code review" anchor, so compliant subagents see the broadening clauses before the narrowing ones.
- Stderr stripped from the report file by default; runner writes a `*-subagent-review.trace.log` to a gitignored local path for in-flight forensic inspection.

**Defers:**

- Backward compatibility with the old artifact triplet names. Consumer repos `/soa update` only at clean checkpoints between phases; no dual-name reader logic and no migration script are needed.
- Persistence of forensic traces beyond worktree lifetime. The operator-in-the-loop inspection model is the assumed audit mechanism for v1.
- Structured findings parsing. The report prose remains the canonical findings record; finding-id → patch-sha mapping is not in scope.
- Bulk re-classification of historical pre-Phase-14 ledger artifacts. Existing rows in committed ledgers stay byte-identical to their committed state.
- Reworking the adversarial-review rubric itself. Phase 14 reorders the prompt prologue; it does not change the rubric's content or finding taxonomy.

---

This phase exists because the first full-phase run of the Phase-13 subagent-review pipeline (codogotchi `phase-02`) produced a ledger that systematically mislabeled what happened. Across nine tickets, every codex-exec run was stamped `skipped` with bogus `sandbox_denied`/`rate_limit` reasons despite the model itself self-reporting `runnerStatus: completed` in the report body. Separately, several `clean` claude-cli rows shipped alongside follow-up `[subagent-review]` patch commits — the ledger said "no findings worth acting on," the git history said otherwise.

The product issue is trust in the ledger as a primary-source audit trail. When `outcome: skipped` and `outcome: clean` both routinely mean "the subagent actually completed and findings exist in the report," a reader has to triangulate against report prose and git log to discover what really happened. Phase 13 made the pipeline structurally honest (advisory-only runner, inline prompt + response capture, honest skip on real failure). Phase 14 makes the ledger semantically honest so the structural honesty produces a trustworthy artifact in routine use.

## Phase Goal

This phase should leave the product in a state where:

- A reader can open a `*-subagent-review.ledger.json` file and learn — from the JSON alone — whether the review actually ran, whether findings were acted on, and whether anything was consciously deferred, without cross-referencing report prose or git log.
- Codex-cli runs that actually completed are recorded as `completed`, with `clean | patched | deferred` outcome depending on what the primary did next. Sandbox-denied and rate-limited runs are still recorded honestly when they really occur, but the runner no longer confuses model stderr noise for runner failure.
- Subagent selection is operator-explicit. The orchestrator accepts `--subagent <claude-cli|codex-cli>` (strict enum) at `execute` / `resume` time; a project-level default lives in `orchestrator.config.json:subagentRunner`. Missing both is a hard error. No SoA-shipped silent default. The optional `--primary <kind>` flag (free-form; defaults to `"unknown"`) captures primary identity per-row in the ledger; cross-family is documented best practice rather than an enforced mechanism. Multi-primary scenarios are captured naturally as multiple ledger rows.
- When the operator's specified subagent fails availability, the fallback chain selects the other configured runner. The ledger records `runnerKind` (what actually ran) plus `fallbackFrom` (what the operator originally requested) so same-family-by-fallback is distinguishable from same-family-by-choice.
- Genuine rate-limit, network, and prompt-processing failures route to the configured fallback runner rather than dead-ending as `skipped`. The ledger records `skipped` only when every configured runner is genuinely unavailable.
- The artifact triplet on disk reads coherently — `prompt → report → ledger` — instead of conflating mechanism (`runner.json`) with slot, or repeating `subagent-review-outcome` redundantly.
- The PR-open step refuses to open a PR when the ledger would be silently false: reviewed files modified without a `[subagent-review]` commit, or actionable findings unacknowledged.
- The adversarial prompt the primary agent writes is biased — by section order — toward using the spec-permits-real-bug and human-review escape valves rather than reading the narrowing language as an exhaustive constraint.

## Committed Scope

Five surfaces of work are locked in for this phase. Exact ticket boundaries belong to decomposition; the product contract is fixed here.

### Runner selection, naming, and classification fidelity

- The `codex-exec` runnerKind value is renamed to `codex-cli` across the ledger schema, runner config, CLI flags, help text, docs, and skill prose. `claude-cli` retains its name. Future runners follow the `<tool-family>-cli` convention. The phase ships only the new name; no dual-name fallback for old artifacts.
- The codex-cli runner step trusts the model's self-reported `runnerStatus` trailer when present and parseable. External signals (sandbox refusal, rate-limit indicators) are accepted as authoritative only when the trailer is absent or the model self-reported a non-`completed` status.
- The runner records both signals in the ledger when they disagree, so a future reader sees `runnerSelfReport: completed` alongside the final classification — disagreement is auditable, not hidden.
- Real sandbox-denied and rate-limit cases stay honestly classified per the availability predicate below. The phase does not weaken honest-skip semantics; it sharpens the boundary between "actually failed" and "completed with stderr noise."
- Subagent selection is operator-explicit. `/soa execute` and `/soa resume` accept `--subagent <claude-cli|codex-cli>` as a strict enum. A project-level default field `subagentRunner` lives in `orchestrator.config.json` so operators with a habitual default need not pass the flag every invocation. Precedence: `--subagent` flag > `orchestrator.config.json:subagentRunner` > hard error with a message pointing at cross-family best-practice docs. SoA ships no built-in silent default. This replaces the `--preferred-runner` flag from Phase 13.
- The optional `--primary <kind>` flag (with project-level default in `orchestrator.config.json:primaryAgent`) records primary-agent identity per ledger row. Values are free-form strings — `claude`, `codex`, `cursor`, `composer`, `copilot`, `aider`, etc. — because the flag is information-only and does not drive orchestrator behavior. Defaults to `"unknown"` if neither flag nor config provides a value. The `-cli` suffix is reserved for `--subagent` (it signals a headless-runner contract); `--primary` values omit it.
- Each ledger row records a single `primaryAgent` value reflecting what was true at that invocation. Multi-primary scenarios (start ticket under claude, hit rate-limit, resume under codex) are captured across multiple rows in the append-only ledger. No array-per-row is needed; the row-wise history tells the multi-primary story.
- v1 supports only `claude-cli` and `codex-cli` as subagent review runners. At least one is assumed available on the operator's machine; the orchestrator does not architect for the "neither available" case beyond honestly skipping. Supporting additional frontier subagent runners is deferred.
- When the operator-specified subagent fails the availability predicate, the fallback chain selects the other configured runner rather than recording `skipped` immediately. The ledger row records `runnerKind` (what actually ran) plus `fallbackFrom: <originally-requested>` (what the operator asked for). Same-family-by-fallback is therefore distinguishable from same-family-by-choice.
- Cross-family review is documented best-practice in the `--subagent` help text, the `soa` skill, and the delivery-orchestrator docs — but the orchestrator does not enforce it. Operator chooses; ledger records. Post-hoc analysis can compute cross-family-achievement as `primaryAgent != runnerKind` whenever both are claude-cli or codex-cli.
- A runner is **unavailable** when any of the following holds: binary missing, invocation errors before producing output, runner returns an authentic rate-limit signal, network failure during invocation, or the runner fails to process the prompt (e.g., parse error, timeout, contract violation). Any unavailability triggers fallback to the other runner. The ledger row records `outcome: skipped` only when every configured runner is genuinely unavailable.
- "Authentic rate-limit signal" is defined by each runner's known rate-limit indicator and is part of the runner config — not inferred from stderr text. This is the boundary that prevents the regression where stderr noise gets mistaken for rate-limit (the codex-cli misclassification the audit caught).
- A runner is **unavailable** when any of the following holds: binary missing, invocation errors before producing output, runner returns an authentic rate-limit signal, network failure during invocation, or the runner fails to process the prompt (e.g., parse error, timeout, contract violation). Any unavailability triggers fallback to the next runner in the configured chain. The ledger row records `outcome: skipped` only when every configured runner is genuinely unavailable.
- "Authentic rate-limit signal" is defined by each runner's known rate-limit indicator and is part of the runner config — not inferred from stderr text. This is the boundary that prevents the regression where stderr noise gets mistaken for rate-limit (the codex-cli misclassification the audit caught).

### Ledger outcome vocabulary

- The ledger outcome enum expands from `clean | skipped` to `clean | patched | deferred | skipped`. Semantics:
  - **clean** — review ran; no actionable findings; no follow-up needed.
  - **patched** — review ran; primary applied at least one `[subagent-review]`-labeled commit.
  - **deferred** — review ran; primary consciously declined to patch, with rationale recorded.
  - **skipped** — review did not produce a usable report (rate-limited, sandbox-denied, runner unavailable, contract violation).
- The ledger gains a `schemaVersion` field. Phase 14 ships version 1; future schema changes bump it. Readers that don't recognize the version fall back to permissive parsing rather than crashing.
- The ledger row for `patched` records the commit SHA(s) in `patches: [...]`. The row for `deferred` records the rationale string in `reason`. The row for `clean` and `skipped` leaves both empty.

### Outcome derivation and PR-open reconciliation

- Between the existing `adversarial-review` step and the `open-pr` step, the orchestrator runs an outcome-reconciliation pass that observes git state since `reviewedHeadSha`.
- If a commit subject contains `[subagent-review]` and touches files in the reviewed paths, the orchestrator appends a `patched` ledger row referencing the commit SHA.
- If files in the reviewed paths were modified since `reviewedHeadSha` but no `[subagent-review]` commit subject is present, the orchestrator blocks PR open and prompts the primary to either re-tag the commit or record an explicit `deferred` with rationale.
- If the report contains actionable findings and no commit modified reviewed paths, the orchestrator blocks PR open and prompts the primary to either patch, run `bun run deliver subagent-review record-deferred --reason "..."`, or run `--acknowledge-clean` (overrides actionable findings only with an explicit operator action).
- The `record-deferred` CLI affordance writes a `deferred` ledger row, replacing the ad-hoc `operator-recorder` runnerKind workaround used once in codogotchi `P2.01`.

### Artifact naming hygiene

- The triplet renames to:
  - `*-subagent-review.prompt.md` (was `-subagent-adversarial-prompt.md`)
  - `*-subagent-review.report.md` (was `-subagent-review-outcome.md`)
  - `*-subagent-review.ledger.json` (was `-subagent-runner.json`)
- The orchestrator and CLI write only the new names. There is no dual-name fallback for old artifacts; consumer repos `/soa update` only at clean phase checkpoints.
- Internal references in docs, skills, retrospectives templates, and orchestrator code update to the new names.
- The `runnerKind` field in the ledger keeps its name — it correctly describes a row's invocation mechanism. Only the file naming changes.

### Prompt prologue reorder and stderr discipline

- The adversarial-review template (`docs/template/delivery/adversarial-review-template.md`) reorders its prologue so the broadening clauses — "you may add extra attack surfaces when your independent repo read finds a plausible ticket-relevant failure path" and "Findings for human review captures anything off-scope but real" — appear in the opening directive block before the narrowing "not a general code review" anchor.
- Existing prompt-authoring guidance in agent-facing skills updates to reference the reordered template.
- The runner step strips stderr from the `*-subagent-review.report.md` file. Only the model's final report text is persisted to the report.
- A `*-subagent-review.trace.log` sibling file captures stderr locally in the worktree. The file is added to gitignore so it never enters PR diffs; its lifetime is bounded by the worktree.
- The pre-existing `runnerStatus` block in the report remains the model's self-report; the ledger's external classification is recorded separately and reconciled per the codex-exec fidelity scope above.

## Explicit Deferrals

- **Dual-name backward compatibility.** Consumer repos accept a clean-cutover rename at `/soa update`; no fallback reader logic for `*-subagent-runner.json` or `*-subagent-review-outcome.md` ships.
- **Migration of historical ledgers.** Pre-Phase-14 ledger files stay byte-identical to their committed state. No re-classification of past `clean`-mislabeled rows. Operators who want retrospective truth can read the audit doc that motivated this phase.
- **Forensic trace persistence beyond worktree lifetime.** Trace lives locally, gitignored, evaporates with worktree cleanup. The audit-trail contract for v1 is that the operator inspects suspicious outcomes pre-closeout.
- **Structured findings parsing.** The report markdown stays the canonical findings record. Mapping individual finding-ids to individual patch SHAs is not in scope; the `patched` row captures commit-level granularity only.
- **Adversarial rubric content changes.** The seven diff-derived classes, the three finding-discipline clauses, and the required output format are unchanged. Only prologue section order moves.
- **External AI PR-review triage.** Unrelated machinery; Phase 14 does not touch CodeRabbit / native PR review polling.
- **Multi-runner concurrency.** The runner step remains single-runner with documented fallback. Parallel cross-agent review is not in scope.
- **Subagent review runners beyond claude-cli and codex-cli.** v1 supports only these two as subagent runners; adding gemini-cli, copilot-cli, or other frontier runners is deferred. The `<tool-family>-cli` naming convention is established now so future additions compose naturally, but no other runner adapter ships in Phase 14.
- **Architecting for "neither claude nor codex available" on the operator machine.** At least one is assumed installable; both-missing is an install problem the operator fixes. Multi-tenant runner-availability matrix work is a children-of-anton concern.
- **Finding suppression / acknowledgment vocabulary beyond `acknowledge-clean`.** A single explicit override exists for the rare "subagent flagged things the primary agrees are non-issues" case. No richer suppression taxonomy ships.

## Exit Condition

When Phase 14 is done, a freshly delivered ticket demonstrates the new fidelity path end-to-end. A codex-exec review that completes is recorded as `outcome: completed` with `clean | patched | deferred` reflecting actual primary action — not `skipped` with a bogus reason. A claude-cli review that finds nothing actionable produces a `clean` row; one that prompts a follow-up patch commit produces a `patched` row referencing the commit SHA. A pure-defer case produces a `deferred` row with rationale captured at the CLI step. The PR-open step refuses to open a PR when the ledger would be silently false. Artifact files on disk read `prompt → report → ledger` in their names. The adversarial prompt prologue presents broadening clauses before narrowing ones. Stderr does not pollute the committed report file. Documentation, skills, and templates describe the same flow. A reader can audit the ledger and trust what it says without cross-checking report prose or git log.

## Retrospective

`required` — Phase 14 changes the durable ledger schema, the artifact filename contract, and the PR-open reconciliation behavior. All three are operator-workflow surfaces and later-phase assumptions ride on them. The retrospective should compare a fresh post-Phase-14 delivery against the codogotchi `phase-02` audit findings and record whether the ledger now stands alone as a trustworthy artifact.

`Trigger:` product-impact | architecture/process impact | durable-learning risk
