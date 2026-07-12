# Phase 05: Subagent Review Clarity and PR Scope Propagation

**Delivery status:** Drafted in planning; pending product-plan approval.

## TL;DR

**Goal:** Reduce operator and agent mis-execution caused by ambiguous guidance, while preserving a guidance-first posture and using real-world delivery signal to decide whether enforcement is needed later.

**Ships:**

- Clear, unambiguous guidance for subagent review defaults and override behavior
- Explicit adversarial-review posture guidance for subagent review prompts
- Canonical template-authority guidance for planning and decomposition flows
- PR metadata/title behavior that consistently uses ticket metadata already present in tickets, including scope (alongside type)

**Defers:**

- Hard enforcement and guardrails that block execution when guidance is ignored
- Broad policy automation beyond the guidance surfaces touched in this phase
- Platform-specific support matrix expansion for additional cross-agent subagent pairings

---

Recent delivery sessions exposed avoidable ambiguity in operator/agent guidance. The result was not feature failure; it was workflow drift: incorrect assumptions about subagent selection defaults, non-adversarial review prompting, and template-shape drift from canonical sources. In parallel, PR metadata behavior in downstream use showed that ticket `type` is reflected while ticket `scope` can be dropped in practice despite being available in ticket docs.

This phase intentionally ships guidance and metadata-contract clarity first, then uses live execution results to determine if a follow-up hardening phase is warranted.

## Phase Goal

This phase should leave the product in a state where:

- A developer or agent can determine subagent review selection behavior without ambiguity: override value is canonical when present; same-type execution-agent subagent is the default when absent.
- Subagent review prompts are framed as adversarial hole-finding, not intent-verification checklists.
- Planning/decomposition flows treat canonical templates as the source of truth rather than modeling file shape from older delivery docs.
- Orchestrated PR metadata uses both ticket `type` and ticket `scope` when constructing PR titles/metadata surfaces, so scope is not silently omitted.

## Committed Scope

### Subagent review behavior clarity

- Clarify, in operator/agent guidance surfaces, the exact default and override behavior for subagent selection.
- Remove wording that can be interpreted as a baked-in default to a specific override example value.
- Ensure examples are explicitly labeled as examples, not fallback behavior.

### Adversarial subagent review posture

- Add explicit guidance that subagent review prompts must assume implementation holes and surface them.
- Prohibit rationalizing away noticed issues in review prompt guidance.
- Make checklist-only framing explicitly non-goal for subagent review.

### Canonical template authority clarity

- Clarify that canonical templates are the only format reference for product planning and decomposition outputs.
- Clarify that existing delivery docs, especially older phases, are not template references for new artifacts.
- Keep this as guidance-first language; no blocking automation in this phase.

### PR scope propagation from ticket metadata

- Ensure orchestrator PR metadata/title generation consumes ticket scope metadata alongside type when constructing conventional-commit style PR titles.
- Eliminate behavior where scope is effectively ignored when it is present and parseable from ticket docs.
- Validate with tests and documentation/examples so downstream repos observe consistent scope-bearing PR titles.

### Outcome-based phase validation

- Define and use operational success checks (not doc-presence checks only) to evaluate whether guidance changes altered behavior in real use.
- Capture whether incidents recur to inform the next hardening decision.

## Explicit Deferrals

- **Guidance enforcement automation:** no new hard gates, lint rules, or runtime blockers in this phase.
- **Broad orchestrator policy hardening:** deferred until live usage data indicates guidance is insufficient.
- **Cross-agent pairing expansion:** no new validated execution/review agent combinations are added in this phase.
- **General PR metadata redesign:** this phase is limited to honoring existing ticket metadata contract (type + scope), not redesigning all PR metadata strategy.

## Exit Condition

Guidance surfaces in scope express subagent-review defaults/override and adversarial posture unambiguously, and planning/decomposition guidance clearly identifies canonical template sources. In real delivery usage after these updates, there are no new incidents of: (a) default subagent-selection misread, (b) checklist-style subagent review prompts, or (c) template drift caused by using existing delivery docs as format references. PR titles/metadata produced by the orchestrator consistently include scope when ticket scope is present, with tests and docs/examples reflecting that contract.

## Retrospective

`required` — this phase changes operator workflow guidance and defines a deliberate learn-before-hardening loop; retrospective output is required to decide whether a follow-up enforcement phase should be scheduled.
