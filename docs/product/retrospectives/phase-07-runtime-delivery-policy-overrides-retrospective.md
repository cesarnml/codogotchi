# Phase 07 Retrospective — Runtime Delivery Policy Overrides

## Scope delivered

Five tickets across PRs #23–#27 on the `agents/p7-0N-*` branch stack:

- **P7.01** — `RunPolicy` type, `runPolicy?: RunPolicy` in `DeliveryState`, `deriveRunPolicyFromConfig`, `normalizeRunPolicy`, `syncStateWithPlan` forward, `loadState`/`repairState` wrappers
- **P7.02** — CLI flag parsing (`--boundary-mode`, `--subagent-review-policy`, `--pr-review-policy`, `--review-subagent`, `--same-review-subagent`), `resolveRuntimePolicyOverrides`, `start` case re-stamping, `cspell.json` review-artifact exclusion
- **P7.03** — `detectRunPolicyDivergence`, `formatRunPolicyDivergenceError`, `patchRunPolicyWithFlags`, `--baseline <orchestrator|run-policy>` parsing, divergence refusal wired into `runDeliveryOrchestrator`, `loadState` wrapper returning `hadPersistedRunPolicy`
- **P7.04** — `formatRunPolicy`, `run_policy= [persisted]` line in `formatStatus`
- **P7.05** — `start-here.md` and `delivery-orchestrator.md` doc updates, this retrospective

## What went well

**TDD enforced clean contracts at every boundary.** Writing the Red tests first before touching any implementation code forced each ticket to expose pure, testable functions (`deriveRunPolicyFromConfig`, `resolveRuntimePolicyOverrides`, `detectRunPolicyDivergence`, etc.) rather than inlining logic into the CLI runner. Every ticket's tests import only the module under test — no orchestrator integration required — which made the Red→Green cycle fast and the diffs easy to audit.

**`hadPersistedRunPolicy` as a load-layer concern was the right call.** The initial instinct was to add a `runPolicySource: 'persisted' | 'derived'` discriminant to `state.json`. Moving that detection into the `loadState` wrapper return value keeps the concern transient (gone after the check) and avoids leaking a new persistent field for what is essentially a one-shot load-time question. The principle: detect at the boundary where you have the information, don't persist what you only need once.

**Subagent review found real bugs on every ticket.** The adversarial prompt produced actionable findings on P7.01 (`null` vs `undefined` runPolicy guard), P7.02 (whitespace-only `--review-subagent`), P7.03 (`start` missing from `DIVERGENCE_EXEMPT`, unsafe `as` casts in `patchRunPolicyWithFlags`), and P7.04 (no `[persisted]` label distinguishing persisted from config-derived lines). None of these were caught by the initial implementation pass. The pattern is reliable: think of the subagent as a second reviewer with adversarial priors, not a rubber stamp.

**Separating `resolveRuntimePolicyOverrides` from `cli-runner.ts` paid off immediately.** Having a pure function that takes `ParsedCliArgs` + raw config and returns a patched config made P7.02 unit tests trivial and kept the precedence logic auditable in one place. When P7.03 needed to build on it for `--baseline=orchestrator`, the `resolvedConfig` (which already had explicit overrides baked in) was cleanly available at the right point in the runner.

## Pain points

**Review artifact spellcheck failures were an avoidable friction.** The P7.01 review artifacts (`.fetch.json`, `.triage.json`) landed in `docs/product/delivery/phase-07/reviews/` which was not in `cspell.json`'s `ignorePaths`. This caused a new spellcheck failure in P7.02 that had to be diagnosed and patched mid-ticket. **Avoidable waste**: the `ignorePaths` entry should have been pre-configured when the `reviews/` directory was first introduced in the delivery orchestrator, not discovered at first use.

**The `loadState` return-type change had a wider surface than expected.** Changing `loadState` from `Promise<DeliveryState>` to `Promise<{ state; hadPersistedRunPolicy }>` required updating the call site, the inline `parsed` type annotation, and the destructuring — three separate edits that were all necessary but individually small. **Expected cost** for a meaningful behavioral change; no redesign would eliminate this entirely, but grouping the two concerns in a single named type (`LoadStateResult`) would make future return-type expansions cheaper.

**Qodo's free-tier billing notification was triaged as `needs_patch` by the AI triager** for both P7.03 and P7.04. The fix was a manual `record-review clean` with a note, but the operator has to recognize the pattern and override. **Expected cost** — billing notices from review bots will always surface as comments. The triager's heuristic of "unresolved comment = needs_patch" is correct in the general case; the fix is operator awareness, not a triager rule change.

## Surprises

**`start` needed to be exempt from divergence checking.** The initial divergence guard blocked `start`, which is exactly the command that re-stamps `runPolicy` from current config when explicit flags are present. Blocking `start` on divergence was self-defeating — the very command that resolves the divergence was being prevented from running. The subagent caught this in P7.03. The lesson: when writing divergence refusal logic, enumerate explicitly the commands that _resolve_ divergence and exempt them, not just the idempotent ones.

**`patchRunPolicyWithFlags` needed narrower types than `string`.** The first draft accepted `boundaryMode?: string` and cast with `as`, relying on CLI-layer validation. The subagent flagged this as a type safety gap — the exported function can manufacture structurally invalid `RunPolicy` objects if called programmatically. Changing to the actual union types (`TicketBoundaryMode`, `ReviewPolicyStageValue`) required importing them into `state.ts` but eliminated the unsafe casts. Worth doing: exported helpers should be safe without trusting caller discipline.

**The `[persisted]` label on `run_policy=` wasn't in the original spec** but was clearly necessary once the formatted output was tested. Without it, the status block shows `boundary_mode=cook` (from config) and `run_policy=boundary_mode=gated ...` (persisted) with no textual signal that these are different sources. The subagent caught it; the fix was a three-character `[persisted]` suffix. Spec omissions of this kind — "how does the operator know which line governs?" — are best caught by reviewing the actual formatted output rather than reasoning about it abstractly.

## What we'd do differently

**Pre-configure review-artifact `ignorePaths` at directory creation time.** When introducing a new directory that will receive auto-generated JSON artifacts (review fetch/triage outputs), add it to `cspell.json`'s `ignorePaths` in the same commit that creates the directory, not when the first artifact is written. This is a one-line change that would have prevented the mid-phase spellcheck breakage in P7.02.

**Return a named type from `loadState` from the start.** `Promise<{ state: DeliveryState; hadPersistedRunPolicy: boolean }>` is readable but benefits from a named type alias (`LoadStateResult`) that can absorb future additions (e.g., `hadLegacyMigration`, `normalizedFields`) without expanding the destructure everywhere. The original choice of returning raw `DeliveryState` was sensible before divergence detection existed; the wrapper now owns more concerns and a named return type would make that contract explicit.

**Write a narrow operator-workflow integration test earlier.** The unit tests (pure functions) were thorough, but there was no test that ran `runDeliveryOrchestrator` end-to-end with a fake state that had a persisted diverged `runPolicy` and verified the error message. That gap means the integration wiring (the divergence check in `cli-runner.ts`) was never tested against a real invocation — it was only audited by reading the code. A small integration test with a mocked state file would have caught the `start` exemption bug before the subagent did.

## Net assessment

The stated goals were achieved. Operators can start and resume orchestrated delivery runs with explicit runtime policy overrides; the resolved policy persists correctly; resume refuses silent drift with clear refusal text and exact recovery commands; and status output shows the active `run_policy [persisted]` line. The subagent review process caught four real bugs across four tickets, validating the adversarial-prompt model. The phase stayed within its approved bounded scope (no policy-consumer plumbing, no preset profiles, no per-ticket policy history).

## Follow-up

- **Plumb `state.runPolicy` into actual consumers** (`startTicket`, `recordPostVerify`, `applyAdvanceBoundaryMode`) so the persisted policy governs execution, not just display. Currently these still read from `context.config`. This was intentionally deferred from P7.04 — it belongs in a bounded engineering epic focused on policy-consumer wiring.
- **Add a `reviewsPaths` entry to `cspell.json` template** in `.son-of-anton/` so new consumer repos get the exclusion automatically on first sync.
- **Add a `LoadStateResult` named type** to `cli-runner.ts` and update the `loadState` wrapper signature to use it.

---

_Created: 2026-05-10. PRs #23–#27 open (stacked, awaiting developer closeout)._
