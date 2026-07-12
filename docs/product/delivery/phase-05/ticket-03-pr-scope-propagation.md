# P5.03 PR Scope Propagation from Ticket Metadata

Size: 2 points
Type: fix
Scope: pr-metadata

## Outcome

- PR titles produced by the orchestrator use the ticket's `Type:` field as the Conventional Commit type and include scope when the ticket's `Scope:` field is populated: `type(scope): subject [P.NN]`
- PR titles for tickets without a `Scope:` field continue to produce `type: subject [P.NN]` (no parens, no regression)
- Both cases are covered by tests

## Red

- In `tools/delivery/test/orchestrator.test.ts`, add two test cases to the existing `buildPullRequestTitle` describe block:
  1. Ticket with `scope: 'pr-metadata'` → title contains `(pr-metadata)`
  2. Ticket with `scope: undefined` → title does not contain `(`
- Run `bun run ci:quiet` and confirm the new tests fail (scope is currently not materialized into `TicketState` so `ticket.scope` is `undefined` for all tickets)
- Commit with suffix `[red]`: `test(P5.03): PR title includes scope from ticket metadata [red]`

## Green

- Root cause: `tools/delivery/state.ts` — the explicit object literal constructing `TicketState` from `TicketDefinition` in `syncStateFromScratch` does not assign `scope`; `buildPullRequestTitle` in `pr-metadata.ts` is already correct
- Fix: add `scope: definition.scope` to the `TicketState` construction object in `syncStateFromScratch` (alongside `id`, `title`, `slug`, `ticketFile`)
- Confirm: `grep -n "scope" tools/delivery/state.ts` now shows the assignment
- Run `bun run ci:quiet` — new tests pass; no existing tests regress
- Commit with suffix `[green]`: `fix(P5.03): propagate ticket scope into TicketState for PR title [green]`

## Refactor

- None — single-line fix; no extraction or restructuring warranted

## Review Focus

- Confirm the fix is in `syncStateFromScratch`, not in `buildPullRequestTitle` (that function is already correct)
- Confirm there is no other construction site for `TicketState` from a definition that would also need the same fix — search for all object literals that spread or assign `id`, `title`, `slug`, `ticketFile` together
- Verify the new tests use a real ticket fixture file path (or mock `parseTicketScope`) rather than relying on filesystem side-effects
- Confirm unscoped tickets still produce clean titles without parens

## Rationale

> Append here when behavior or trade-offs change during implementation.

Red first: new tests fail because `ticket.scope` is always `undefined` in current `TicketState`
Why this path: one-line assignment fix at the construction site is the smallest change; all downstream consumers (`buildPullRequestTitle`) already handle scope correctly
Alternative considered: parsing scope at PR-open time instead of at state construction — rejected; scope belongs on the state object so it is inspectable and durable across sessions
Deferred: scope validation (format constraints enforcement beyond what the ticket template already documents)
Contract note: `TicketDefinition.scope` is `string | undefined`; `TicketState` inherits via `TicketDefinition &`; the assignment must preserve optionality
Patch addendum: `TicketDefinition.type` is now parsed from the ticket's `Type:` metadata and carried into `TicketState` alongside `scope`; `buildPullRequestTitle` no longer derives the Conventional Commit type from the ticket filename. Filename-derived type was intentionally removed because decomposition already generates canonical `Type:` and `Scope:` metadata for every ticket.
