# P14.06 Prompt prologue reorder, docs/skills/template alignment, phase retrospective

Size: 2 points
Type: docs
Scope: subagent-review
Red: skip

## Outcome

- The adversarial-review template at `docs/template/delivery/adversarial-review-template.md` reorders its prologue. The broadening clauses appear in the opening directive block, before the narrowing "not a general code review" anchor:
  - "You may add extra attack surfaces when your independent repo read finds a plausible ticket-relevant failure path."
  - "Findings outside the three finding-discipline clauses belong in **Findings for human review** — anything off-scope but real is welcome there."
- The seven diff-derived classes, three finding-discipline clauses, required output format, and other rubric content are **unchanged**. Only the prologue section order moves.
- Agent-facing skills under `.agents/skills/**` that reference subagent-review prompt authoring (especially `son-of-anton-ethos`, `pr-review`, and `grill-me` if they touch this surface) are updated to reflect:
  - The new `--subagent` + `subagentRunner` operator-explicit selection model.
  - The new outcome vocabulary (`clean | patched | deferred | skipped`).
  - The new reconciliation step and `--ack-reconciliation` flag.
  - The new artifact triplet names.
  - The new prologue order in the template.
- `docs/template/delivery/delivery-orchestrator.md` is updated to describe the `reconcile-subagent-review` step between `subagent-review` and `open-pr`, the operator-explicit `--subagent` contract, the hard-block-on-silent-lie semantics, and the new artifact triplet.
- `docs/template/overview/start-here.md` updates any subagent-review references to point at the new flow.
- `README.md` is updated wherever it describes subagent-review behavior or names artifact files.
- The retrospective template at `docs/template/stubs/retrospective.template.md` (if present) is updated to reference the new ledger schema fields (`primaryAgent`, `runnerSelfReport`, `fallbackFrom`, `schemaVersion`).
- The Phase 14 retrospective lands at `docs/product/retrospectives/phase-14-subagent-review-classification-and-outcome-fidelity-retrospective.md`. It compares the post-Phase-14 delivery experience against the codogotchi P2 audit findings and records whether the ledger now stands alone as a trustworthy artifact (per the product plan's Retrospective contract).
- **Green test target:** `Red: skip`, but `bun run verify:quiet` (prettier + lint) must succeed across all edited docs and skills. Human review at PR is the quality gate for prose content.
- **Manual demo command:** read `docs/template/delivery/adversarial-review-template.md` start-to-finish. The first encountered guidance about scope after the opening "You are conducting an adversarial review" framing must include the broadening clauses (extra surfaces / human-review bucket) before the narrowing clause ("not a general code review"). Read three agent-facing skill files at random; verify references to subagent-review semantics match Phase 14 (no stale `codex-exec`, `--preferred-runner`, or old triplet names).

## Red

`Red: skip` — this ticket is doc-only. Per the ticket template:

> **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value.**

Writing tests that assert specific prose wording in templates and skills couples the test suite to legitimate prose evolution without adding quality signal. Spellcheck + link-check + human review at the PR are the acceptance gates.

No `[red]` commit.

## Green

- **Prompt prologue reorder.** Edit `docs/template/delivery/adversarial-review-template.md`. Move the "you may add extra attack surfaces" sentence and the "Findings for human review" bucket description into the opening directive block, before "Your job is not a general code review." Do not change rubric content.
- **Agent-facing skill updates.** Walk `.agents/skills/**/SKILL.md` and `.agents/skills/**/*.md`. Update references to:
  - `codex-exec` → `codex-cli`
  - `--preferred-runner` → `--subagent` (with mention of `orchestrator.config.json:subagentRunner` default)
  - `*-subagent-adversarial-prompt.md` → `*-subagent-review.prompt.md`
  - `*-subagent-review-outcome.md` → `*-subagent-review.report.md`
  - `*-subagent-runner.json` → `*-subagent-review.ledger.json`
  - Outcome vocabulary: mention `deferred` alongside `clean | patched | skipped`
  - Reconciliation step and `--ack-reconciliation` flag where relevant to the skill's domain
- **Delivery orchestrator doc update.** Edit `docs/template/delivery/delivery-orchestrator.md` to describe `reconcile-subagent-review` step, operator-explicit `--subagent` contract, and new artifact triplet. Add a "Phase 14 changes" subsection if a phase-change log convention exists.
- **start-here.md.** Update `docs/template/overview/start-here.md` references.
- **README.md.** Update repo-root README wherever subagent-review behavior or artifact names appear.
- **Retrospective template.** If `docs/template/stubs/retrospective.template.md` (or similar) exists, update it to reference the new ledger fields.
- **Phase retrospective.** Write `docs/product/retrospectives/phase-14-subagent-review-classification-and-outcome-fidelity-retrospective.md` using the `soa-write-retrospective` skill at `.agents/skills/write-retrospective/SKILL.md` for section structure. The retrospective should specifically address:
  - Did the codex-cli classification fix close the audit's primary failure mode?
  - Did the operator-explicit `--subagent` flag prove sufficient, or did operators hit friction that suggests revisiting the silent-default decision?
  - Did the PR-open reconciliation block cause genuine operator-hostility, or was the educational cost bounded as predicted?
  - Did the artifact triplet rename surface any consumer-repo-discoverable old-name references that the P14.04 sweep missed?
  - Does the post-Phase-14 ledger genuinely stand alone as a trustworthy audit artifact (the product plan's Exit Condition)?
- Run `bun run verify:quiet`; resolve any prettier or lint issues.
- Commit: `docs(P14.06): prompt prologue reorder, docs/skills/template alignment, phase 14 retrospective`

## Refactor

- If multiple skill files repeated the same Phase 14 description, consolidate to a single canonical paragraph and have other skills cross-reference rather than duplicate. Only consolidate what you touched.

## Review Focus

- **Prologue reorder fidelity.** Verify the broadening clauses literally appear before the narrowing clause when reading top-to-bottom. The mechanism here is human reading order — anything that defeats it (e.g., placing the broadening clauses inside a collapsible section, putting them after a section break) reproduces the original "buried directive" failure mode.
- **Rubric content unchanged.** A diff of the template should show only section reorder, not edited rubric text. The seven diff-derived classes, three finding-discipline clauses, and required output format must remain byte-identical.
- **Skill drift completeness.** This ticket's stop condition fires when updating one skill reveals another references the old contract. Use `git grep` for stale terms (`codex-exec`, `--preferred-runner`, old triplet filenames) before declaring the alignment complete.
- **Retrospective honesty.** The retrospective must compare against the audit's specific failure modes (codex-cli mislabeling, `clean`-vs-`patched` collapse, dishonest `skipped` reasons). A retrospective that summarizes "what we shipped" without testing against the audit findings is not honest per the product plan's Retrospective contract.
- **Cross-consumer impact.** Some skill text is read by primary agents in consumer repos. After this ticket lands and `/soa update` propagates, primary agents will read the updated guidance. Verify the prose is correct for the consumer-repo context (e.g., `docs/template/...` paths translate to `.son-of-anton/docs/template/...` when read from a consumer repo).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: N/A — `Red: skip` doc-only ticket; `post-red` recorded skip structurally.

Why this path: Reordered the adversarial template prologue in-place (broadening clauses before narrowing anchor) without touching rubric bytes below the opening block. Updated operator-facing surfaces (`delivery-orchestrator.md`, `start-here.md`, `README.md`, `AGENTS.soa.md`, `son-of-anton-ethos`) to describe Phase 14 reconciliation and artifact triplet in one pass. Left historical ticket files under `docs/product/delivery/phase-{10,13,14}/` unchanged — they are delivery archaeology, not consumer discoverability.

Alternative considered: Mass-editing every historical ticket and retrospective to replace `--preferred-runner` / `codex-exec`. Rejected — high churn, low signal; grep confirmed agent-facing paths were already clean after P14.02–P14.04.

Deferred: No `retrospective.template.md` exists in `docs/template/stubs/`; ledger field guidance lives in the Phase 14 retrospective and orchestrator Phase 14 subsection instead.

Contract note: `grill-me` and `pr-review` skills unchanged — they do not describe subagent-review runner selection. `soa` skill already pointed at orchestrator doc as gospel.
