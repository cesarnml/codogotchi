# P19.02 Prune works for every window kind

Size: 2 points
Type: fix
Scope: menubar
Red: required

## Outcome

- `FloatingPetWindowPool.pruneSession` resolves the target `(origin, sessionId)` from the window's `resolvedIdentity` (P19.01) instead of gating on `WindowKey.sessionIdentity` — Prune now works for `.origin` (folded or solo/default-sentinel) and `.combined` windows, not just `.session`-keyed ones.
- `FloatingPetPromptCapabilities.hasActiveSession` — the gate that decides whether "Sync Label"/"Prune Session" even appear in the right-click menu — is true whenever a resolved identity exists for the window, not only when `windowKey.isSessionKeyed`. Today these menu items are entirely absent for `.origin`/`.combined` windows; after this ticket they're present and functional.
- No change to menu copy/alert text (P19.03) or the mode badge (P19.04) — this ticket is the backend targeting fix and the boolean gate only.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- `FloatingPetWindowPoolTests`: pruning a `.origin` window backed by multiple folded sessions removes the currently-winning session's `state.d` slice (not a no-op); pruning a `.origin` window backed by a solo `"default"`-sentinel slice removes that slice; pruning a `.combined` window removes the winning origin's session slice. Each locks in a case that silently no-ops today.
- A capability-gate test (new or extended `FloatingPetPromptBuilder`-adjacent test) proving `hasActiveSession` is `true` for a resolved `.origin`/`.combined` window and the menu item set includes Prune/Sync Label.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P19.02): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement the smallest change that makes the failing tests pass
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Verify `pruneSession` still declines to act when no resolved identity exists at all (e.g. a window mid-teardown with no backing slice) — this ticket widens the gate, it must not remove it entirely.
- Confirm the `"default"`-sentinel case is pruned through the exact same code path as a real session, not a special-cased branch — per the phase's committed scope, this is not architecturally different from any other identity-loss case.
- Double-check `SessionPruner.pruneSession`'s `origin`/`sessionId` arguments are sourced from the resolved identity, not the window's own `WindowKey`, for every call site this ticket touches.
- Intentionally deferred: Prune confirmation/menu-item text changes (P19.03); the mode-indicator badge (P19.04).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
