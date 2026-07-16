# P18.06 Cutover and role reversal

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- The composed pipeline drives the app: `update()` = build tick input → `derive` → `diff` → `apply`, with `PoolMemory` stored on the pool and out-of-band user actions running their pure transitions + immediate effects as the authoritative path.
- Roles reverse: the old pipeline now shadows via the recording proxy's stub direction (stub `currentFrame` reads through to the live windows), with the same comparator and log-only divergence surfacing.
- Launch-time env var `CODOGOTCHI_POOL_ENGINE=legacy` flips the roles back (old drives, new shadows) as the rollback path — read once at startup, no runtime toggling.
- `FloatingPetWindowPool`'s public surface (`setVisible`, `pruneSession`, `hideAllOtherWindows`, `resetPromptTimer`, `sessionNumber`, `sessionDisplayLabel`, `controller(for:)`, `activeOrigins`, `blockedOrigins`, `pendingSessionKeys`, `ttlDismissedWindowKeys`, `replacePet`, `clearAttentionBubbles`, `pruneHiddenKeysWithoutBackingSlice`, …) is unchanged — `MenubarApp` and menu wiring untouched.
- Full existing suite (900+) green against the composed pipeline — pre-existing behavioral tests are the cutover's primary regression net and must pass unmodified except where they reached into old-pipeline internals.
- A fresh dogfood build is installed; the post-cutover reversed-shadow soak window opens at this ticket's close.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Failing tests first: engine selection (default = new drives / old shadows; `CODOGOTCHI_POOL_ENGINE=legacy` = reversed), and public-surface reads (`sessionNumber`, `blockedOrigins`, `pendingSessionKeys`, `ttlDismissedWindowKeys`) served from the new engine's outputs.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.06): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Swap the authoritative path; keep the old pipeline compiled and shadowing. No deletion in this ticket.
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Any pre-existing test that had to be *modified* to pass is a red flag — each modification needs an explicit justification (internal-reaching test vs. genuine behavior delta; the latter is a divergence-policy event, not a test edit).
- Public-surface reads must come from the new engine's state, not linger on old-pipeline fields that are now shadow-only.
- Rollback flag: verify the legacy path is genuinely the P18.05 configuration (old drives through proxies), not a third hybrid.
- Reversed shadow honesty: the old pipeline's stub controllers must see the same reader inputs and frame reality as the live windows, or the soak logs phantom divergences.
- Intentionally deferred: deletion of the old pipeline, shadow machinery, and the flag (P18.07).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.

**Stop condition at close:** the phase pauses here until the deletion gate is met — the same rare-branch checklist repeated under the reversed shadow on the daily driver, with zero unexplained divergences. Developer confirms before P18.07 begins.
