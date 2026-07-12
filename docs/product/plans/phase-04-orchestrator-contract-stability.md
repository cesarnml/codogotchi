# Phase 04: Orchestrator Contract Stability

**Delivery status:** Decomposed and approved — `docs/product/delivery/phase-04/` exists and Phase 04 is ready to start.

## TL;DR

**Goal:** Make the delivery orchestrator resilient to non-behavioral change so iterative improvements do not look like regressions.

**Ships:**

- Stable machine-readable workflow/state-guard error identity for delivery-tooling flows that currently expose only prose
- A defined optional-DI safety pattern for delivery helpers so newly added optional hooks fail safe by default
- Test migrations that assert stable contract surfaces instead of treating human-facing error wording as a strict API
- Docs describing which orchestrator surfaces are intentionally stable and how contributors should extend them

**Defers:**

- Broad repo-wide error-framework adoption outside delivery tooling
- Unifying every delivery-tool error under one pattern, including low-level platform/config/runtime failures
- General CLI copy/style cleanup beyond the workflow/state-guard surfaces covered by this phase
- Review-vendor behavior, polling-window behavior, and other external-review ergonomics not implicated by these contract failures

---

Phase 03 exposed two forms of brittleness in the orchestrator. First, adding one optional DI hook (`hasLocalBranchCommits`) broke unrelated tests because the new call site behaved as if the dependency were required. Second, enriching wrong-state messages broke tests that had implicitly treated error prose as a stable API. Neither failure reflected a behavior regression, but both consumed debugging and review time as if they had.

Phase 04 addresses that trust problem directly. The point is not nicer wording or more abstractions for their own sake; it is to make orchestrator evolution cheap when behavior is unchanged and explicit when behavior really does change.

## Phase Goal

This phase should leave the product in a state where:

- A wording-only improvement to a workflow/state-guard error message does not break unrelated tests, because tests assert a stable contract rather than incidental prose
- Adding a new optional dependency hook to existing delivery helpers does not change behavior unless the hook is actually supplied
- Contributors can identify which delivery-tool error surfaces are machine-stable, which remain human-facing only, and how each should be tested

## Committed Scope

### Stable workflow error contract

- Define a machine-stable contract for orchestrator workflow/state-guard failures where agent flow or tests currently depend on English error text
- Apply that contract only within delivery tooling, and only to workflow/state-guard surfaces that need stable identity
- Preserve human-readable guidance in thrown errors, but separate stable identity from mutable explanatory prose
- Cover the current wrong-state / next-command style failures that Phase 03 enriched and exposed as brittle

### Optional-DI safety boundary

- Define the delivery-tool stance for optional dependency injection hooks: optional means the new behavior only runs when the hook is explicitly provided
- Implement a consistent code pattern or helper that makes this safe-by-default rule easy to follow
- Apply that pattern to the relevant delivery helper surfaces implicated by the Phase 03 regression class

### Contract-oriented test strategy

- Migrate affected delivery-tool tests away from asserting full or brittle substring matches on workflow/state-guard prose where a stable contract is available
- Add targeted regression tests proving that optional-DI additions and wording-only message changes do not break unrelated behavior
- Keep human-facing message coverage where it is genuinely important, but narrow those assertions to the intended stable fields/tokens rather than whole phrases

### Contributor guidance

- Document the boundary: which delivery-tool errors are contract-bearing, how optional DI must be extended, and how tests should assert those surfaces
- Record the rationale so later phases do not reintroduce prose-as-API or required-by-accident optional hooks

## Explicit Deferrals

- **Repo-wide typed/custom error framework:** this phase is delivery-tool local only; application code and unrelated tooling are out of scope
- **All delivery-tool errors:** low-level config parsing, platform command failures, GitHub adapter failures, and other non-workflow errors do not need to migrate in this phase
- **Global CLI message unification:** status output, PR-body copy, review notes, and other operator-facing strings stay out of scope unless they are part of the workflow/state-guard contract
- **Standalone PR review-state recording:** standalone `ai-review` remains behavior-first and stateless; this phase does not add durable standalone post-verify/subagent-review artifacts

## Exit Condition

Delivery-tool workflow/state-guard failures expose a stable machine-readable identity alongside their human guidance, and the affected test suite asserts that stable surface instead of brittle prose. Optional dependency hooks in the targeted delivery helpers are safe by default: adding a new optional hook no longer breaks existing callers that do not provide it. A contributor reading the docs can tell which orchestrator contracts are stable, how to extend them, and how to test them. The phase proves the change behaviorally with regression tests that would have failed under the pre-Phase-04 patterns.

## Retrospective

`required` — this phase changes a durable technical/process boundary inside the orchestrator, and the result should be measured by whether later UX or guard improvements stop generating false regressions. Trigger: `architecture/process impact`.
