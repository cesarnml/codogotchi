# P18.07 Old-pipeline deletion and closeout

Size: 2 points
Type: chore
Scope: menubar
Red: skip

## Outcome

- The old imperative pipeline is deleted from `FloatingPetWindowPool` — every superseded step, helper, and stored property; the class is the thin shell (input assembly, stored `PoolMemory`, `derive`→`diff`→`apply` composition, public surface, user-action two-limb methods).
- The shadow machinery (comparator wiring in the tick, divergence logging, stub read-through path) and the `CODOGOTCHI_POOL_ENGINE` rollback flag are deleted. The recording proxy and comparator may survive only where tests use them; nothing shadow-related runs in production.
- The purity gate remains in CI permanently.
- All six product-plan exit conditions verified and recorded (an exit-audit doc in this directory, matching the phase-17 precedent): composition, purity, no-hidden-policy (P18.03 step-mapping artifact reviewed final), tests, shadow evidence (both soak logs summarized, every divergence dispositioned), dogfood.
- `bun run verify` and `bun run ci:quiet` pass; full suite green.
- A dogfood DMG is packaged via `scripts/package-dmg.sh` and installed as the daily driver. No public release, no download-page update.
- The phase retrospective is written: `docs/product/retrospectives/phase-18-pool-derive-diff-apply-retrospective.md` (required — the Track 4 program's closing verdict; mechanically required by the Track 2 execution gate).

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**
- This ticket is deletion + packaging + docs: the existing 900+ suite and the purity gate are the regression net; no new failing test meaningfully precedes a deletion.

## Green

- Delete in dependency order (shadow wiring → flag → old pipeline steps → dead helpers/properties), keeping the suite green at each commit.
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Dead-code sweep: no orphaned old-pipeline property, helper, or comment survives (grep for the step numbering and superseded property names); a leftover stored property silently double-tracking state is the failure mode.
- Exit-audit honesty: each of the six conditions cites its evidence (test names, log summaries, grep output, DMG path) — no asserted-but-unverified rows.
- Divergence-log dispositions: every logged divergence across both soaks is either a ledger-entried old-pipeline fix, a matched new-engine fix, or the one named title-seam exemption. Anything else blocks closeout.
- README / `start-here` currency check per the ticket-completion checklist (Track 4 status changes).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
