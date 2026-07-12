---
name: soa-preflight
description: Template-compliance gate between /soa decompose and /soa execute. Reads implementation-plan.md and all ticket files for a phase and checks them against the canonical stubs in docs/template/stubs/. Reports a structured PASS/FAIL checklist. Must be called and must PASS before /soa execute is invoked.
---

# SoA Preflight

Run the template-compliance checklist for a decomposed delivery phase. This is the gate between decompose (plan files written) and execute (orchestrator begins implementation). A phase that fails preflight must be corrected before `/soa execute` is called.

## Trigger

`/soa preflight <phase-N>` — e.g. `/soa preflight phase-06`

Also triggered automatically by `/soa decompose` after files are written and developer approves the breakdown, before surfacing the execute prompt.

## What It Checks

### Implementation Plan (`implementation-plan.md`)

Required sections (exact heading text):

- `## Epic`
- `## Product contract`
- `## Grill-Me decisions locked`
- `## Ticket Order`
- `## Ticket Files`
- `## Exit Condition`
- `## CI Baseline`
- `## Review Rules`
- `## Explicit Deferrals`
- `## Stop Conditions`
- `## Phase Closeout`

Cross-checks:

- Every filename listed under `## Ticket Files` must exist on disk in the delivery directory.
- Every ticket listed under `## Ticket Order` must have a corresponding file in `## Ticket Files`.
- `## Phase Closeout` must contain `Retrospective: required` or `Retrospective: skip`.

### Each Ticket File (`ticket-NN-*.md`)

**Metadata (lines 3–6, immediately after the `# PN.NN` title):**

| Field    | Valid values                                             |
| -------- | -------------------------------------------------------- |
| `Size:`  | `N point` or `N points` (integer N)                      |
| `Type:`  | `feat`, `fix`, `docs`, `refactor`, `test`, `chore`       |
| `Scope:` | lowercase letters, digits, hyphens only (optional field) |
| `Red:`   | `required` or `skip`                                     |

**Required sections (exact heading text):**

- `## Outcome`
- `## Red`
- `## Green`
- `## Refactor`
- `## Review Focus`
- `## Rationale`

**Rationale sub-labels** (must appear in `## Rationale` body):

- `Red first:`
- `Why this path:`
- `Alternative considered:`
- `Deferred:`
- `Contract note:`

**`Red: skip` consistency rules:**

- If `Red: skip` in metadata, the `## Red` body must contain the word `skip` and a brief reason.
- Doc-only tickets (`Type: docs`) must have `Red: skip`.

## How to Run It

1. Read the canonical templates:
   - `docs/template/stubs/implementation-plan.template.md`
   - `docs/template/stubs/ticket.template.md`

   In a consumer repo these live at `.son-of-anton/docs/template/stubs/`.

2. Locate the delivery directory: `docs/product/delivery/<phase>/`

3. Read `implementation-plan.md`. Check every required section. Check cross-references between `## Ticket Order` and `## Ticket Files`.

4. Glob all `ticket-NN-*.md` files in the delivery directory. For each:
   - Parse metadata lines.
   - Check required sections.
   - Check Rationale sub-labels.
   - Apply `Red: skip` consistency rules.

5. Output a compliance report (see format below).

6. If any check fails: **do not proceed to `/soa execute`**. List all failures, explain what is missing or wrong, and ask the developer to fix before continuing.

## Output Format

```
## Preflight: phase-06

### implementation-plan.md
✅ ## Epic
✅ ## Product contract
✅ ## Grill-Me decisions locked
✅ ## Ticket Order
✅ ## Ticket Files
✅ ## Exit Condition
⚠️  ## CI Baseline  ← placeholder present but baseline not yet recorded (acceptable before first ticket)
✅ ## Review Rules
✅ ## Explicit Deferrals
✅ ## Stop Conditions
✅ ## Phase Closeout  (Retrospective: skip)
✅ Ticket Files cross-reference: all 9 listed files exist on disk

### Tickets (9)

| Ticket | Size | Type | Scope | Red | Sections | Rationale |
|---|---|---|---|---|---|---|
| P6.01 | ✅ | ✅ feat | ✅ contracts | ✅ required | ✅ 6/6 | ✅ 5/5 |
| ...   | ...  | ...      | ...           | ...          | ...     | ...     |

### Result

PASS — 9/9 tickets clean, implementation plan complete.
Ready for: /soa execute phase-06
```

If failures exist:

```
FAIL — 3 issues found. Fix before running /soa execute.

1. implementation-plan.md: missing ## Stop Conditions
2. ticket-03: Red: required but ## Red body contains no test description
3. ticket-07: Rationale missing "Contract note:" sub-label
```

## CI Baseline Warning

The `## CI Baseline` section in `implementation-plan.md` is expected to contain a placeholder at preflight time (before the first ticket starts). A placeholder is not a failure — emit a `⚠️` warning but do not block. A recorded baseline (date + pass/fail summary) is required before reporting PASS on tickets P6.02+.

## Placement in Lifecycle

```
/soa plan       → product plan approved
/soa decompose  → ticket files written, developer approves breakdown
/soa preflight  → compliance gate (this skill) ← HERE
/soa execute    → orchestrator begins implementation
```

`/soa decompose` should surface the preflight prompt automatically after writing files:

> Files written. Run `/soa preflight phase-N` to verify template compliance before starting execution.
