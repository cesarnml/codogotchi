---
name: soa-write-retrospective
description: Write a phase or engineering epic retrospective. Use when completing a phase, epic, or significant standalone PR. Output goes to docs/product/retrospectives/<plan-path>-retrospective.md or docs/product/retrospectives/ee<N>-retrospective.md.
---

# Write Retrospective

Retrospectives are AI-readable artifacts first, human-readable second. Future agents read them at phase starts and epic planning to understand what patterns to repeat, what to avoid, and what the spec missed. Section naming must be consistent across retrospectives so agents can reliably extract signal.

## Required Sections (in order)

### 1. Scope delivered

What shipped: PR numbers, branch name, scope items as a short list. One paragraph max. This is the factual anchor — without it the retro floats.

### 2. What went well

Patterns to repeat. Include _why_ they worked, not just that they did. "TypeScript caught it" is noise. "TypeScript caught it because the type was narrow enough to make the error unambiguous at the call site" is signal. Aim for reusable lessons, not praise.

### 3. Pain points

Friction sources with root cause. Distinguish **avoidable waste** (something that could be designed away) from **expected cost** (inherent to the work). Both are worth recording but they imply different follow-up.

### 4. Surprises

Things not in the spec — good and bad. This is the highest-signal section for future AI readers: surprises are exactly what won't appear in docs or specs. A surprise that led to a fix belongs here with full context. A surprise that was benign still belongs here so the next agent doesn't have to rediscover it.

### 5. What we'd do differently

Architectural or process choices that hindsight would change. Distinct from pain points: pain points are about what slowed you down; this is about what you'd redesign. Include the original reasoning so the retro doesn't just say "we were wrong" — say _why_ the original choice looked correct and what new information changed it.

### 6. Net assessment

Verdict on whether the stated goals were achieved. Required for engineering epics (which have an explicit hypothesis). Optional for phases without a specific hypothesis. One paragraph. Don't hedge — say whether it worked.

### 7. Follow-up

Concrete next actions. Avoid "consider X" — prefer "fix the stale test assertions before Phase 16 branches" or "add enforcement in EE7." If the follow-up has a natural home (a future epic, an open issue), name it.

---

## What to omit

- **Timeline evidence** — delivery debugging artifact, not a learning. If a timeline is needed, it belongs in an incident report or effectiveness evaluation, not here.
- **Ticket-by-ticket tables** — effectiveness evaluation material. Use `docs/product/retrospectives/<plan>-effectiveness-evaluation.md` for that.
- **Vague summaries** — "overall the phase went well" without evidence. If you can't point to something specific, skip the sentence.

## Naming and placement

- Product Phase: `docs/product/retrospectives/phase-<N>-<slug>-retrospective.md`
- Engineering epic: `docs/product/retrospectives/ee<N>-<slug>-retrospective.md`
- Close with: `_Created: <date>. PR #N open/merged._` or equivalent factual closer.
