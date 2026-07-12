# PN.NN [Ticket Title]

Size: 2 points
Type: <feat|fix|docs|refactor|test|chore>
Scope: <conventional-commit-scope> (optional — lowercase letters, digits, and hyphens only)
Red: <required|skip>

## Outcome

- [Bullet: what is demonstrably true when this ticket is done]
- [Each bullet should be independently verifiable]

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**
- [Write a failing test that proves the behavior is missing]
- [Tests should be behavior-first, not implementation-first]
- Run the test suite and confirm the new test fails
- Commit with suffix `[red]`: `test(PN.NN): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- [Implement the smallest change that makes the failing test pass]
- [Do not over-engineer — just make it green]

## Refactor

- [Extract, rename, or simplify without changing behavior]
- [Only refactor what you touched — no opportunistic cleanup]
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- [What a reviewer should pay attention to]
- [Public API shape, error ergonomics, edge cases]
- [What was intentionally deferred and why]
- For tickets that build a client-side helper constructing an API URL: verify the server-side handler reads and uses the params that `<helper>` sends — check both sides of the boundary, not just each in isolation.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
