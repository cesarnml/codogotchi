# soa-preflight: Design Rationale

_Added: 2026-05-29_

## Problem

The orchestrator is nitpicky about template compliance — it reads `implementation-plan.md` and ticket files expecting exact section headings, metadata fields, and Rationale sub-labels. When a decompose pass misses a required section (even a non-obvious one like `## CI Baseline` or `## Stop Conditions`), the orchestrator either fails mid-delivery or silently skips behaviour that depends on the missing content.

The issue surfaced concretely during Phase 06 decomposition: the implementation plan was missing 6 of 11 required template sections. The gap was only caught by a manual post-decompose audit.

## Solution

`/soa preflight <phase-N>` is a lightweight compliance gate that runs after `/soa decompose` writes files and before `/soa execute` starts. It reads the canonical templates from `docs/template/stubs/` and verifies every required section, metadata field, and cross-reference.

## Lifecycle Position

```
/soa decompose  →  files written, developer approves
/soa preflight  ←  compliance gate (new)
/soa execute    →  orchestrator begins
```

The `decompose` skill should surface the preflight prompt automatically after writing files — not as a hard stop, but as a clear next step.

## What It Checks

**implementation-plan.md:** 11 required sections, `## Ticket Files` ↔ disk cross-reference, `## Ticket Order` ↔ `## Ticket Files` cross-reference, retrospective declaration in `## Phase Closeout`.

**Each ticket:** `Size`/`Type`/`Scope`/`Red` metadata format, 6 required sections, 5 Rationale sub-labels, `Red: skip` consistency rules (doc-only tickets must skip, skip tickets must include a reason).

**CI Baseline:** warns (⚠️) if placeholder is not yet recorded — this is expected before the first ticket starts and is not a blocking failure.

## Why Not Automate It in the Decompose Step?

Decompose already has a hard stop (developer approval). Adding automated template validation there would couple the decompose step to template changes and make it harder to iterate on templates independently. Preflight is a separate, replaceable gate — if the template changes, only `SKILL.md` needs updating, not the decompose flow.

## Skill Location

`.agents/skills/preflight/SKILL.md` — syncs to consumer repos as `soa-preflight` via `soa-sync.sh`.
