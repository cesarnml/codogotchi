# Phase N: [Phase Title]

**Delivery status:** Product plan approved state goes here. Update this line when decomposition starts or completes so it matches repo reality.

[Optional: one or more `Origin issue: #<N>` lines, one issue per line — only present when this plan was created via `/soa plan phase-N: issue #<N> ...` (or via an explicit multi-issue trigger listing several). `/soa decompose` copies these verbatim into `implementation-plan.md`'s `## Epic` section, which is what actually triggers the `Closes #<N>` PR-body lines (one per issue) on the phase's final ticket. Do not add this field by inferring an issue from context — it is only ever set by the explicit plan-trigger syntax. A single-line comma-separated form (`Origin issue: #78, #83`) is not supported — one canonical form, one line per issue.]

## TL;DR

**Goal:** [One sentence — what problem does this phase solve or what capability does it add?]

**Ships:** [Bullet list of concrete deliverables — what will exist that doesn't today.]

**Defers:** [What is explicitly out of scope for this phase.]

---

[2–3 sentences of context. Why now? What is the product state before this phase ships? What is the forcing function?]

## Phase Goal

[This phase should leave the product in a state where:]

- [Observable outcome 1 — something a user or developer can verify]
- [Observable outcome 2]
- [Observable outcome 3]

## Committed Scope

[Describe what is locked in for this phase. Be specific — vague scope creates ticket bloat. Group related work under subheadings if the phase has multiple distinct areas.]

### [Area 1]

- [Specific behavior or change]
- [Specific behavior or change]

### [Area 2]

- [Specific behavior or change]

## Explicit Deferrals

- [What is intentionally not in scope. Be specific — "future work" is not a deferral.]
- [Name the thing and the reason it's deferred, not just the phase it might land in.]

## Exit Condition

[Prose. What is demonstrably true when this phase is done? What can you show someone?]

## Retrospective

`skip` or `required` — [one sentence why]
