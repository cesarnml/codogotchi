# Issue Tracking

Use a small, explicit issue system that mirrors the docs structure.

## Hierarchy

- Epic: a phase-level outcome such as `Phase 01 MVP`
- Ticket: a reviewable implementation slice within an epic
- ADR: a durable technical or tooling decision that affects multiple tickets

Avoid adding extra layers unless the project grows beyond what this structure can hold.

## Naming Convention

Use stable ticket identifiers in docs, issues, PRs, and review notes.

Examples:

- `P1.01 CLI Skeleton And Config Loading`
- `P1.02 RSS Fetch And Parse`
- `P1.06 SQLite Dedupe And Run History`
- `P2.01 Scheduling`

Recommended epic names:

- `Phase 01 MVP`
- `Phase 02 Real-World Feed Compatibility`
- `Phase 03 Post-Queue Lifecycle`

## Point System

Use Fibonacci-style points with a strong preference for `2` and occasional `3`.

- `1 point`: under 1 hour, trivial or highly local
- `2 points`: 1-3 hours, normal ticket size for this repo
- `3 points`: 3-5 hours, larger but still reviewable
- `5 points`: too large for the current repo rules, split before implementation
- `8 points`: epic-level work, not a normal ticket

## Workflow

For each ticket:

1. write the first failing test
2. implement the smallest code to go green
3. refactor for clarity
4. capture a short rationale note in the delivery ticket doc for reviewers and future threads
5. stop for review before the next ticket

After a phase or epic is functionally complete, run one bounded polish pass before starting the next phase.

Use that pass to:

- simplify architecture around the completed scope
- strengthen behavior-level tests around the completed scope
- update docs for any newly stable interfaces

Do not add next-phase features during this pass.

## Learning Artifact

Each ticket or PR should include a short rationale section with these prompts:

- `Red first:` what behavior failed first
- `Why this path:` why this implementation was the smallest acceptable way to go green
- `Alternative considered:` one plausible alternative and why it was rejected for this ticket
- `Deferred:` what was intentionally not built yet

## Epic Status

Track active and closed epics here as your project evolves.

| Epic         | Status | Notes |
| ------------ | ------ | ----- |
| _(none yet)_ | —      | —     |

## Source Of Truth

- phase goals live in `docs/product/plans/` (create this in your consuming repo)
- ticket plans live in `docs/product/delivery/`
- cross-cutting workflow rules live in `docs/template/delivery/` (in this template repo)
- durable decisions live in `docs/04-decisions/` (create this in your consuming repo)

Do not bury ticket scope only in GitHub issue comments. The matching doc file should remain readable without external context.
Do not bury implementation rationale only in chat history. Preserve the short learning artifact in the delivery ticket doc.
If later review or validation produces non-redundant findings, append them to the same `## Rationale` section instead of creating a parallel rationale artifact.
