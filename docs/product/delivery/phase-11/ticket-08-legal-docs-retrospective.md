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

Red first: N/A — doc-only ticket (no automated test; PR review is the gate).
Why this path: Privacy/Terms are written as static Astro pages reusing the site's existing `Base` layout + sidebar/section pattern (mirroring `docs/spritesheet.astro`), so they inherit the nav, footer, and design tokens for free and need no new infra. Copy is original and adapted to codogotchi's actual data handling (Convex storage, Google/GitHub/email auth, Resend verification, aggregate download counts, no analytics) rather than copied from the codex-pets references. The community-content disclaimer + `admin@codogotchi.app` takedown line was lifted from the gallery page into the global `Footer.astro` so it appears site-wide alongside the new Privacy/Terms links.
Alternative considered: A single combined `/legal` page — rejected; separate `/privacy` and `/terms` routes are the conventional shape, easier to deep-link from the footer, and match user expectation.
Deferred: A cookie/consent banner (none needed — no tracking cookies or third-party analytics); a per-pet in-app "Report" button (takedowns intentionally route through `admin@codogotchi.app` email per the product plan); GIF-file export and other deferrals tracked in the implementation plan.
Contract note: The ticket's "update `docs/template/overview/start-here.md`" line was **not** applied — in this consumer repo that file lives under the `.son-of-anton/` git subtree and is generic SoA orchestrator workflow documentation (zero codogotchi/marketplace content). Editing subtree content would create drift clobbered on the next `soa update`. The equivalent user-visible product documentation (`README.md` + `plugins/hatch-codogotchi/README.md`) was updated instead. The launch-readiness checklist is recorded at `docs/runbooks/phase-11-launch-readiness.md` and is explicit that it gates the *public announcement*, not the code merge.
