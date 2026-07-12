# P18.05 Shadow tick — old drives, new shadows

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- Every poll tick runs both pipelines: the old `update()` drives the app through recording proxies (real controllers wrapped); the new `derive` runs on the same tick input against its own threaded `PoolMemory`; the comparator diffs them.
- Out-of-band user actions apply their pure `PoolMemory` transitions in parallel with the old pipeline's mutations, so the shadow's memory stays honest between ticks.
- Divergences: assert in tests/debug builds; in release/dogfood, log to NSLog + `~/.codogotchi/logs/shadow-divergence.log` with replayable tick-input fingerprints — never fatal, never user-visible.
- Old pipeline behavior is byte-for-byte unchanged (proxies are transparent); full existing suite green against the driving path; purity gate green.
- A dogfood build with the shadow live is installed as the daily driver — the pre-cutover soak window opens at this ticket's close.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Failing tests first: an end-to-end shadow-tick test proving (a) a tick where both pipelines agree produces no divergence records, and (b) a seeded disagreement (temporarily perturbed derive input) produces exactly one structured record and does not affect the driving pipeline's windows.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.05): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Wire the shadow into `FloatingPetWindowPool.update()` (or its call site in the polling driver) with the old pipeline authoritative; keep the shadow's failure modes contained (a thrown error in shadow code must not break the tick).
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Isolation: no code path where the shadow influences the driving pipeline — including shared mutable inputs (readers must be invoked once and fanned out, or invoked identically).
- User-action dual-write: each action must update both worlds atomically with respect to the next tick; a missed transition shows up as a phantom divergence that erodes trust in the log.
- Divergence records: are they actually replayable (fingerprint sufficient to reconstruct the table row)? Each real divergence found during soak should become a regression test.
- Log hygiene: bounded file growth, no sensitive content.
- **Divergence policy is binding during this ticket's soak:** an old-pipeline bug found via divergence is fixed in the old pipeline first, in a separate commit with a review-gap ledger entry, then the new engine must match.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.

**Stop condition at close:** the phase pauses here until the pre-cutover gate is met — the scripted rare-branch checklist (cap overflow + eviction, grandfather both directions, hide-while-capped, manual Prune, own↔minimalist↔combined transitions, all three window shapes) exercised under shadow on the daily driver, with zero unexplained divergences. Developer confirms before P18.06 begins.
