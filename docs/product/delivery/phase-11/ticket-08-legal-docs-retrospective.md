# P11.08 Legal pages, docs + retrospective

Size: 2 points
Type: docs
Scope: docs
Red: skip

## Outcome

- **Privacy** and **Terms** pages are published on the site (adapted, not copied, from the codex-pets references), reachable from the footer alongside the community-content disclaimer.
- Documentation reflects the shipped marketplace: `README.md` and `docs/template/overview/start-here.md` updated where user-visible behavior/commands changed (the new `codogotchi add` command, `/gallery`, `/upload`); the `hatch-codogotchi` README cross-links the gallery as the publish destination.
- A **launch-readiness checklist** is recorded (not code): ~10 seeded pets live in `/gallery`, `admin@codogotchi.app` intake confirmed, operator kill-switch verified, Privacy/Terms published — explicitly the gate for the *public announcement*, separate from code completion.
- The **phase retrospective** is written.

## Red

- `Red: skip` — doc-only ticket (branch touches only `.md`/legal/static-content files). No automated test; human review at the PR is the gate.

## Green

- Write the Privacy/Terms pages, the doc updates, the launch-readiness checklist, and the retrospective.

## Refactor

- N/A (doc-only).

## Review Focus

- Privacy/Terms are **adapted**, not copy-pasted, and accurately describe codogotchi's actual data handling (Convex storage, OAuth providers, what's collected).
- The launch-readiness checklist is unambiguous about being a *go-public* gate, not a definition-of-done for the code.
- Retrospective follows `soa-write-retrospective` structure.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: N/A — doc-only ticket
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [any deviation from the ticket metadata contract]
