# P4.01 Stable workflow contracts and DI safety

Size: 3 points
Type: fix
Scope: delivery-tooling

## Outcome

- Targeted workflow/state-guard failures in the delivery tool expose a stable machine-readable identity alongside human-readable guidance
- Optional DI hooks in the targeted delivery helpers are safe by default: the new behavior runs only when the hook is explicitly supplied
- Affected delivery-tool tests assert stable contract surfaces rather than brittle prose where a machine-stable contract exists
- Regression coverage proves that wording-only workflow message changes and new optional-DI hooks do not break unrelated behavior

## Red

Write failing tests before any implementation. Keep the scope tight: target workflow/state-guard surfaces and the optional-DI regression class that Phase 03 exposed.

**`tools/delivery/test/ticket-flow.test.ts` and `tools/delivery/test/orchestrator.test.ts` - workflow/state-guard contract:**

- Add tests that expect targeted wrong-state / guard failures to expose stable machine-readable identity rather than relying on legacy prose-only matching
- Cover at least the current `open-pr` wrong-state family and one adjacent state-guarded command that already depends on next-command guidance
- Keep one narrow human-guidance assertion where useful, but do not let full English phrasing remain the primary contract

**`tools/delivery/test/p4-01.test.ts` - optional DI safety regression:**

- Reproduce the Phase 03 regression class directly: a helper with an added optional hook must not throw or alter behavior when existing callers omit that hook
- Prove the optional hook path does run when the hook is explicitly supplied
- If a small helper/pattern is introduced, test it directly in addition to the higher-level orchestration path

**`tools/delivery/test/p4-01.test.ts` - wording-only churn resistance:**

- Add a regression test that demonstrates targeted workflow behavior remains valid even if explanatory prose changes, as long as the stable machine-readable contract stays the same

Run the relevant test suite, confirm the new coverage fails first, commit:

```text
test(P4.01): lock workflow error contracts and optional DI safety [red]
```

Do not write implementation until this red checkpoint exists on the branch.

## Green

**Delivery-local workflow error contract:**

- Add one small delivery-local error shape for targeted workflow/state-guard failures
- Preserve human-readable guidance for operators, but separate stable identity from mutable explanatory prose
- Apply the contract only to the targeted workflow/state-guard and closely related orchestrator guard failures implicated by this phase

**Optional-DI safety pattern:**

- Add one small helper or code pattern that makes optional hooks fail safe by default
- Apply it to the targeted delivery helper surfaces implicated by the Phase 03 regression class
- Keep the pattern local and obvious; this ticket is not a broader dependency-injection redesign

**Test migration:**

- Update affected tests to assert the stable machine-readable surface where available
- Retain narrow message-content assertions only for stable tokens or operator guidance that is intentionally part of the contract
- Add regression tests proving the previous false-regression modes are gone

## Refactor

- Consolidate any repeated workflow contract construction into one delivery-local chokepoint if it improves readability without widening scope
- Remove or simplify brittle helper code uncovered by the migration, but only within the targeted contract boundary

## Review Focus

- Stable identity remains narrowly scoped to workflow/state-guard and closely related orchestrator guard failures; low-level config/platform/runtime errors must not get swept in accidentally
- Human-readable error guidance still tells the operator what to do next; the new machine-stable layer must not degrade ergonomics
- Optional-DI safety really is safe-by-default for omitted hooks and does not silently change existing code paths
- Tests no longer treat incidental English phrasing as the primary API where a stable machine-readable contract exists

## Rationale

Why this path: the phase exists to harden a boundary, not to create a general-purpose error architecture. One small local workflow-error contract plus one small optional-DI safety primitive is enough to stop the specific false-regression patterns Phase 03 exposed while keeping the implementation reviewable.

Alternative considered: patching tests and call sites individually with no shared primitive. Rejected because it relies on contributor memory rather than establishing a durable extension rule in code.

Deferred: migrating low-level config/platform/runtime failures into the same contract. Those errors are intentionally out of scope for this phase and would inflate the ticket.

Contract note: this ticket originally omitted `Type:` and used the free-form scope `delivery tooling / tests`, which is not conventional-commit compliant. That happened because the active ticket template still documented only an optional `Scope:` line and did not require normalized commit metadata. The ticket now records `Type: fix` and `Scope: delivery-tooling` so the contract is explicit and machine-usable.

Implementation note: the delivered boundary stayed narrow. Stable machine-readable codes were added only to the targeted workflow/state guards touched by this ticket (`open-pr`, `advance`, and the closely related worktree guard), while low-level runtime/config/platform failures remain plain errors. Optional hook execution now goes through one small helper so omitted hooks stay true no-ops and tests can assert that extension rule directly.
