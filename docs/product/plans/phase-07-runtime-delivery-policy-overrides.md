# Phase 7: Runtime Delivery Policy Overrides for Execute/Resume

**Delivery status:** Approved product plan. Committed to `main`.

## TL;DR

**Goal:** Let developers start and resume orchestrated delivery runs with explicit runtime policy control, without editing and committing temporary changes to `orchestrator.config.json`.

**Ships:**

- Runtime policy overrides for `/soa execute` and `/soa resume`, limited to:
  - `ticketBoundaryMode`
  - `reviewPolicy.subagentReview`
  - `reviewPolicy.prReview`
  - review-subagent selection
- A durable run-level policy snapshot in `state.json`
- Explicit precedence and divergence rules between `orchestrator.config.json`, runtime flags, and persisted run policy
- A refusal-and-recovery contract for `/soa resume` when persisted run policy and current repo policy diverge
- Operator-facing output that makes the active run policy visible during execution and resumption

**Defers:**

- Named policy presets or profiles
- Arbitrary runtime override of unrelated orchestrator config keys
- Per-ticket policy snapshots
- Standalone `ai-review` runtime policy expansion

---

Today, temporary delivery-policy changes require editing `orchestrator.config.json` and committing those changes to `main` before starting or resuming a run. That is the wrong boundary for one-off operational choices like boundary mode changes or temporary review-policy adjustments. This phase adds explicit runtime policy controls for `/soa execute` and `/soa resume` while keeping committed repo defaults durable and reviewable.

## Phase Goal

This phase should leave the product in a state where:

- A developer can start a run from `orchestrator.config.json`, patch it with explicit runtime flags, and persist the resolved policy into `state.json`
- A developer can resume a run with explicit runtime changes when needed, including changing boundary/review behavior after an interruption
- `/soa resume` refuses to proceed silently when persisted run policy and current repo policy diverge and the operator has not chosen a baseline
- Active run policy is visible enough in execution/resume surfaces that another operator can tell what rules govern the run

## Committed Scope

### Runtime policy override surface for execute/resume

- `/soa execute <phase|epic>` accepts runtime flags for:
  - `ticketBoundaryMode`
  - `reviewPolicy.subagentReview`
  - `reviewPolicy.prReview`
  - review-subagent selection
- `/soa resume <phase|epic>` accepts the same override flags and may change the active run policy mid-run when the operator passes them explicitly.
- This phase remains strictly scoped to `/soa execute` and `/soa resume`. It does not introduce a general-purpose runtime config system for unrelated orchestrator commands.

### Durable run-level policy snapshot

- `orchestrator.config.json` remains the durable repo default source.
- `state.json` persists one active run-level policy snapshot for the phase run.
- `/soa execute` resolves policy from `orchestrator.config.json` plus explicit runtime flags, then writes the resolved run policy into `state.json`.
- This phase does not persist per-ticket policy snapshots. Policy is tracked at the run level only.

### Explicit review-subagent selection semantics

- The persisted run policy uses an explicit review-subagent selection field rather than overloading `reviewSubagentOverride` with omission sentinels.
- Review-subagent selection distinguishes:
  - same-type fallback
  - explicit concrete override value
- Subagent stage disablement remains part of `reviewPolicy.subagentReview`, not review-subagent selection.
- Operators can intentionally force same-type review-subagent behavior at runtime even when `orchestrator.config.json` defines a concrete override.

### Resume divergence detection and baseline selection

- Divergence detection compares only the bounded policy fields in scope for this phase:
  - `ticketBoundaryMode`
  - `reviewPolicy.subagentReview`
  - `reviewPolicy.prReview`
  - review-subagent selection
- When persisted run policy and current `orchestrator.config.json` agree, `/soa resume` proceeds normally.
- When they diverge and the operator passes no baseline choice, `/soa resume` refuses to continue and shows both policies.
- `/soa resume` supports explicit baseline selection with:
  - `--baseline=orchestrator`
  - `--baseline=run-policy`
- Mixed policy is allowed only by choosing a baseline and then passing explicit override flags.
- `/soa resume --baseline=orchestrator` with no additional flags is a valid explicit action: adopt current repo defaults for the run and continue.

### Precedence and persistence rules

- `/soa execute`: baseline is always `orchestrator.config.json`; explicit flags patch that baseline; the resolved result is written to `state.json`.
- `/soa resume` on divergence: the operator must choose `--baseline=orchestrator|run-policy`; explicit flags patch the chosen baseline; the resolved result is written back to `state.json`.
- `/soa resume` with explicit flags is allowed to change the active run policy midstream and persists the updated result.
- No runtime action in this phase rewrites `orchestrator.config.json`.

### Effective policy observability and operator clarity

- Execution and resume flows expose the active run policy clearly enough that the operator can see what rules are governing the run.
- The resume mismatch refusal includes:
  - persisted run policy
  - current repo policy
  - the exact recovery commands using `--baseline=run-policy` and `--baseline=orchestrator`
  - a note that mixed policy requires explicit override flags
- Visibility requirements are part of the product contract for this phase, not a decomposition-only detail.

### Guardrails and validation

- Unsupported values, invalid policy stages, and contradictory combinations fail before the run continues.
- Validation errors point to accepted values and expected command shape.
- Resume refusal is treated as a guardrail, not as a soft warning or silent fallback.

## Explicit Deferrals

- **Named policy profiles / presets** — no `--profile fast` style abstraction in this phase.
- **Broad dynamic config override** — only the bounded execute/resume policy controls in this phase are overridable.
- **Per-ticket policy history** — the phase does not add immutable per-ticket policy snapshots; the run-level snapshot is sufficient.
- **Standalone `ai-review` parity** — this phase does not extend the same runtime policy model to standalone review flows.
- **Automatic config reconciliation** — runtime decisions do not mutate or normalize `orchestrator.config.json`.

## Exit Condition

An operator can start a run from durable repo defaults, apply explicit runtime policy changes, and have the resolved policy persisted for that run. If the repo defaults later diverge from the persisted run policy, `/soa resume` does not guess: it refuses until the operator explicitly chooses `--baseline=orchestrator` or `--baseline=run-policy`, then applies any requested overrides and persists the new result. The active run policy is visible in the relevant execution/resume surfaces, review-subagent selection distinguishes same-type from concrete override cleanly, and no temporary policy choice requires committing config churn to `main`.

## Retrospective

`required` — this phase changes operator workflow semantics for execute/resume, introduces durable run-policy precedence rules, and is likely to generate follow-up learning about orchestration safety and recovery UX.
