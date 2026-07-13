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

Red first: N/A — `Red: skip` per ticket metadata; deletion + packaging + docs, regression net is the existing 900+ suite and the purity gate, both unmodified and green after this ticket (`bun run ci:quiet`: 628 bun tests + 1146 mac tests, 0 failures).
Why this path: deleted in dependency order (shadow-only files → `LegacyPoolEngine`/`PoolEngine` → dead test premises) as a single coherent commit rather than an artificial multi-commit split, because `LegacyPoolEngine` itself references `NoOpStubWindowController`, so the two halves are not independently compilable/green.
Alternative considered: splitting into two commits (shadow-support-file deletion, then engine deletion) to match the ticket's Green guidance literally — rejected because the intermediate state would not compile, violating "keeping the suite green at each commit."
Deferred: none from ticket scope. Explicitly out of ticket scope and not attempted: the v4 hook-stamped `prompt_started_at` architecture, reader/writer disk-contract changes, and public release/notarization/Sparkle (all named phase-level deferrals in `implementation-plan.md`).
Contract note: **binding stop condition not independently verified.** The implementation plan's P18.06→P18.07 gate requires the reversed-shadow rare-branch checklist to be exercised on the dogfood daily driver with zero unexplained divergences before this ticket's deletion begins, and normally requires a divergence-log disposition table per this ticket's own Review Focus section. No soak-summary doc or divergence log exists under this phase's delivery directory. The developer was asked directly and explicitly answered "No, waive the gate anyway" during the delivery session, accepting the residual risk and stating unexpected behavior will be patched after `v3_preview` lands. Recorded honestly in `docs/product/delivery/phase-18/exit-audit.md` §5 as developer-waived, not as a false PASS.
