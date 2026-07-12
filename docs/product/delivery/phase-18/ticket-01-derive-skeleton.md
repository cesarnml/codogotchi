# P18.01 Derive skeleton — PoolMemory, DesiredWindows, tick core

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `apps/menubar/Sources/Pool/Derive/` exists holding `PoolMemory`, `PoolTickInput`, `DesiredWindows`/`DesiredWindow`, and `PoolDerive.derive(input:memory:) -> (DesiredWindows, PoolMemory)` — all value types, `PoolMemory` and `DesiredWindows` `Equatable`.
- The derive core reproduces `update()` Steps 1–5b and the eligibility bounding as pure logic: off-mode filtering, the idle-frozen TTL clock rule (advance only while not idle; seed on first sight), first-seen (set once), last-updated tracking, last-active election restricted to eligible keys, the sticky HUD-bearer election (re-elect only when the holder leaves in-flight or eligibility), TTL expiry with last-active immunity, and memory bounding to the eligibility window (with the `.combined` prompt-timer exemption).
- `DesiredWindow` fields not yet computed by this ticket (selection, pushes) exist in the type with explicit placeholder semantics documented, so P18.02/P18.03 extend without reshaping.
- Nothing is wired: the live pipeline is byte-for-byte untouched; the new code has no callers outside tests.
- The purity gate runs in CI: a check asserting no file under `Pool/Derive/` imports AppKit.
- Full existing suite green.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Write failing table-driven tests against `derive` first: TTL clock freezing on idle slices, first-sight seeding, last-active immunity, election eligibility (a clock-skewed departed key must not hold immunity), sticky HUD-bearer non-hopping mid-prompt, and memory bounding.
- Include at least one multi-tick fold test (a sequence of `(input, expected memory′)` rows) to prove the fold shape carries state correctly.
- Write the purity-gate check and confirm it would fail on a deliberate `import AppKit` in the new directory.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.01): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement the types and the derive core to make the tables pass — transcribe the semantics of Steps 1–5b (and their inline invariants) from `FloatingPetWindowPool.update()`, do not redesign them.
- Do not implement selection (Step 6c), collapses (6a/6a2/6b), or pushes — placeholders only.

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- `PoolMemory` field-by-field against the pool's stored properties: every cross-tick mutable in `FloatingPetWindowPool` must have a home here or a documented reason it stays shell-owned (there should be none for policy state).
- The idle-frozen TTL clock and election rules carry documented Phase 15 invariants — check the transcription against the source comments, not just the tests.
- Type shape: will `DesiredWindow` survive P18.02/P18.03 extension without breaking `Equatable` or forcing churn?
- Purity gate actually runs in CI, not just locally.
- Intentionally deferred: selection/admission policy (P18.02), push spec (P18.03), any wiring (P18.05+).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
