# Phase 18 - Configured Branch Targets

> Split Son of Anton branch roles so delivery, closeout, and repo-primary references honor explicit operator configuration.

## Epic

Product plan: `docs/product/plans/phase-18-configured-branch-targets.md`

## Product contract

Operators can configure `defaultBranch`, `deliveryBaseBranch`, and `closeoutBranch` as separate required branch roles. Delivery work starts, stacks, rebases, opens PRs, and reports status against `deliveryBaseBranch`; closeout lands completed stacks against `closeoutBranch`; repo-primary references keep using `defaultBranch`.

## Grill-Me decisions locked

- `deliveryBaseBranch` required -> avoids preserving the overloaded `defaultBranch` behavior that Phase 18 removes.
- `closeoutBranch` required -> keeps all branch roles explicit after migration instead of hiding closeout behavior behind fallback rules.
- `/soa update` migration fills both new fields from existing `defaultBranch` -> preserves pre-Phase-18 behavior for consumers, including non-`main` values such as `master`.
- Missing `defaultBranch` during migration resolves the new fields to `main` -> gives legacy or hand-written configs a deterministic pre-Phase-18 target.
- Ticket-file PR links stay on `defaultBranch` -> docs links should point at the repo-primary branch, while stacked PR base metadata continues to show each ticket's actual delivery base.

## Ticket Order

1. `P18.01 Config schema and update migration`
2. `P18.02 Delivery base branch behavior`
3. `P18.03 PR metadata and state repair branch roles`
4. `P18.04 Closeout target branch behavior`
5. `P18.05 Docs and retrospective`

## Ticket Files

- `ticket-01-config-schema-and-update-migration.md`
- `ticket-02-delivery-base-branch-behavior.md`
- `ticket-03-pr-metadata-and-state-repair-branch-roles.md`
- `ticket-04-closeout-target-branch-behavior.md`
- `ticket-05-docs-and-retrospective.md`

## Exit Condition

Phase 18 is done when a maintained test suite can model `defaultBranch: "main"` with `deliveryBaseBranch` and `closeoutBranch` set to different configured targets, and every delivery, PR metadata, state repair, and closeout surface uses the correct branch role. Consumer `/soa update` must also migrate existing configs by adding both required fields from the previous `defaultBranch` value, including non-`main` values.

## CI Baseline

Run `bun run ci:quiet` on `main` before the first ticket starts and record the result here. This snapshot makes per-ticket CI diffs unambiguous - an agent can tell whether a failure is pre-existing or introduced.

> Baseline recorded: 2026-06-28 - `bun run ci:quiet` passed (621 tests, 0 failures).

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Branch-role terminology must stay consistent across code, tests, docs, and operator-facing errors.

## Explicit Deferrals

- No automated promotion from one configured branch role to another.
- No release checklist, version tag, changelog, deployment, or branch-protection workflow.
- No changes to GitHub repository default branch settings.
- No per-phase or per-ticket branch overrides.
- No multi-train branch matrix beyond one delivery base and one closeout target.

## Stop Conditions

- Existing consumer migration cannot preserve the previous configured `defaultBranch` target without unsafe JSON rewriting.
- Delivery and closeout behavior disagree about which branch role owns a surface.
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Phase 18 changes a durable operator workflow boundary by separating repo-primary, delivery-base, and closeout-target branch roles.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-18-configured-branch-targets-retrospective.md`
