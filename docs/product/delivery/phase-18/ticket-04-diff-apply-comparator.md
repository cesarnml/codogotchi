# P18.04 Diff, apply, recording proxy, and comparator

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `diff(desired:current:)` is a mechanical set comparison: spawn / dismiss / update sets keyed by `WindowKey`, with frame-inheritance directives passed through as data — no policy branches (any needed decision is evidence of a P18.03 gap, fixed there).
- `apply` executes a diff against the Phase 17 converged factories: spawn (with directive-driven frame adoption read from the live donor window at execution time), teardown, and per-window pushes straight from `DesiredWindow` fields; performs title resolution for `titleResolutionRequests` (disk cache read-through + write-through) and feeds results back for the next tick's memory. Zero policy decisions.
- A recording `FloatingPetWindowControlling` proxy exists: forwards every call to a wrapped controller while logging pushes per tick; also runnable against a stub (no real window) whose `currentFrame` reads through to a live window by key — both shadow directions covered.
- A field-level comparator diffs recorded old-pipeline behavior + extracted decision sets against a `(DesiredWindows, PoolMemory)` pair: asserts under tests/debug, emits structured divergence records (tick-input fingerprint, field path, both values) for log-only use. Frame directives compared structurally, never CGRect values. The title-seam delay is a built-in exemption.
- Still unwired into the live tick; full existing suite green; purity gate green (diff is pure and lives in `Pool/Derive/`; apply/proxy/comparator live outside it and may import AppKit).

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- Failing tests first: diff set algebra (spawn/dismiss/update partitioning, directive pass-through), apply against mock controllers (push completeness — every `DesiredWindow` field reaches the controller), proxy forwarding fidelity, comparator detection of a seeded single-field divergence and honoring of the title-seam exemption.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P18.04): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Implement the smallest change that makes the failing test pass
- Do not over-engineer — just make it green

## Refactor

- Extract, rename, or simplify without changing behavior
- Only refactor what you touched — no opportunistic cleanup
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Hunt for policy hiding in `apply` — any `if` on domain state (mode, activity, cap, TTL) rather than on diff/spec data is a violation of the phase's fixed constraint.
- Push completeness: a `DesiredWindow` field that apply never forwards is a silent behavior change the comparator can't see from the new side — check field-by-field.
- Comparator exemption mechanism: exemptions must be named and enumerated (currently exactly one), not pattern-matched loosely.
- Proxy: verify the stub direction's `currentFrame` read-through — post-cutover reversed shadowing depends on it (P18.06).
- Intentionally deferred: any wiring into the live tick (P18.05).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
