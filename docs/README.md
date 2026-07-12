# Docs Index

<!-- This directory ships inside the son-of-anton subtree. Consumer repos see it as
     .son-of-anton/docs/template/. The "template/" subdir is named from the consumer's
     perspective — it holds the files consumers copy and reference. Son-of-Anton uses
     its own orchestrator to build itself (ouroboros), so these docs double as live
     delivery guidance for this repo and as the shipped template layer for all consumers. -->

## New to the codebase?

Start with [`docs/how-son-of-anton-works.md`](how-son-of-anton-works.md) — a
newcomer's mental model of the whole system (no prior knowledge assumed), with a
concept→file map. Then follow the reading order below.

## Recommended Reading Order

1. `docs/template/overview/start-here.md` — onboarding and immediate next action
2. `docs/template/delivery/son-of-anton.md` — doctrine and philosophy
3. `docs/template/delivery/delivery-orchestrator.md` — full command reference
4. `docs/template/delivery/issue-tracking.md` — ticket sizing conventions
5. `docs/template/delivery/phase-implementation-guidance.md` — plan and ticket format
6. `docs/template/delivery/tdd-workflow.md` — Red/Green/Refactor implementation contract

## Templates

- `docs/template/stubs/implementation-plan.template.md` — copy this when starting a new phase
- `docs/template/stubs/ticket.template.md` — copy this for each ticket in the phase

## Folder Structure

### `template/overview` — Entry-point docs

- `start-here.md`: onboarding and immediate next action

### `template/delivery` — Delivery doctrine and command reference

- `son-of-anton.md`: why this workflow exists
- `delivery-orchestrator.md`: authoritative CLI command surface
- `tdd-workflow.md`: red-green-refactor implementation contract
- `issue-tracking.md`: Fibonacci sizing and issue conventions
- `phase-implementation-guidance.md`: implementation plan format contract

### `template/stubs` — Starter files for new phases and tickets

- `implementation-plan.template.md`
- `ticket.template.md`

### `product/plans` — Approved product phase plans

### `product/delivery` — Implementation plans and tickets
