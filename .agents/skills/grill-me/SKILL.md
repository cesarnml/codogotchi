---
name: soa-grill-me
description: Stress-test a plan or design by questioning every key assumption until the decision tree is resolved.
---

Question the plan aggressively until key decisions, dependencies, and tradeoffs are explicit.

## Two Modes — Do Not Mix

This skill is invoked in two distinct contexts. **Read the invoking command before asking a single question.**

### Mode 1: `/soa plan` → Product Plan (`docs/product/plans/phase-N.md`)

**What:** Stress-test scope, goals, and success criteria — the _what_ and _why_.
**Output:** A filled-out `docs/product/plans/phase-N.md` using the product-plan template.
**Hard stop:** Do NOT ask about schema design, API routes, ticket breakdown, PR slicing, or implementation details. Those belong in Mode 2. If the developer drifts toward implementation, redirect: _"That's a decompose question — let's lock the product plan first."_

Questions stay at the product level:

- What problem does this phase solve?
- What does success look like to a user?
- What is explicitly out of scope?
- What are the dependencies on other phases or external systems?
- What could kill this phase before it ships?

### Mode 2: `/soa decompose` → Delivery Plan (`docs/product/delivery/phase-N/`)

**What:** Stress-test implementation approach, ticket granularity, and sequencing — the _how_.
**Output:** An approved ticket breakdown ready to write as `implementation-plan.md` + individual ticket files.
**Hard stop:** Do NOT write any files or invoke the orchestrator until the developer explicitly approves the breakdown.

> **Before writing any ticket file:** Read the canonical ticket template at `docs/template/stubs/ticket.template.md`. Do not reference existing delivery docs for format — they may predate the current template and will produce format drift if copied.

Questions go deep on implementation:

- Schema design and migration strategy
- API route structure and failure modes
- Ticket sequencing and PR slice boundaries
- Test strategy per ticket
- Exit conditions per ticket

---

## Mode Compatibility

Works in Plan Mode and Ask Mode. Prefer whichever the developer initiates from; do not switch mid-session.

## Question Protocol

- One question at a time. After the answer, ask the next single best question — never batch.
- Prefix with progress: `Question N of ~M` (M shifts as branches open or close — expected and fine).
- For each question, include:
  - **Recommendation:** your preferred answer and why — be direct, not hedged.
  - **Opposing view:** the strongest case against your recommendation. Steelman it.
  - **Tradeoffs:** brief pros/cons of the main strategies under consideration (bullet list, not prose).
- If the codebase can answer a question, inspect it instead of asking.
- **Mode 1:** walk the decision tree: goals → scope → success criteria → deferrals → dependencies → risks
- **Mode 2:** walk the decision tree: scope → dependencies → sequence → tradeoffs → edge cases → exit conditions

## Required Phase-Closeout Decision

For **product ideation → phases**, decide retrospective status before the plan is final:

- `Retrospective: required | skip`
- `Why:`
- `Trigger:` product-impact | architecture/process impact | durable-learning risk | none

Default:

- **epics:** `required`
- **phases:** `skip` unless the phase changes operator workflow, introduces a durable boundary, creates likely follow-up learning, or changes later phase assumptions

Record it in the implementation plan. Add retrospective work to the final docs/exit ticket only when the plan says `required`.

## Hard Stop After Ticket Decomposition

When used for use case 2, the output is the ticket breakdown — not the start of implementation.

1. Present the full breakdown clearly.
2. Explicitly ask the developer to approve it before any implementation begins.
3. Do not create branches, write code, or invoke the orchestrator until approved.

Skipping this control point bypasses the sequencing requirement (delivery docs committed to main before orchestrator begins) and will corrupt orchestrator state.
