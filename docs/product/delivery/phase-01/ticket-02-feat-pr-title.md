# P1.02 PR title derived from ticket content

Size: 2 points
Scope: pr-metadata

## Outcome

- PR titles follow `type(scope): subject [PXX.XX]` where type and scope come from the ticket, never from git commit history
- `type` is extracted from the ticket filename: `ticket-NN-<type>-<slug>.md` via regex `/^ticket-\d+-([a-z]+)-/`
- `scope` is parsed from an optional `Scope: <area>` metadata line in the ticket doc; omitted from title if absent
- Red test commits (`test(PN.NN): ... [red]`) can never become the PR title
- Ticket template updated with optional `Scope:` line

## Red

Write failing tests for `buildPullRequestTitle` asserting:

- `{ ticketFile: 'ticket-01-fix-state-sync.md', scope: 'cli', id: 'P1.01', title: 'Fix state.json sync in advance' }` → `fix(cli): fix state.json sync in advance [P1.01]`
- Same ticket without `scope` → `fix: fix state.json sync in advance [P1.01]`
- Filename with unrecognized type token → falls back to `feat: <title lowercase> [P1.01]`
- Filename that doesn't match the convention at all → falls back to `feat: <title lowercase> [P1.01]`

Run the test suite and confirm the new tests fail.
Commit with suffix `[red]`: `test(P1.02): assert PR title derives from ticket filename and scope field [red]`
Do not write any implementation until this commit exists on the branch.

## Green

**1. `types.ts` — add `scope` to `TicketDefinition`**

```ts
export type TicketDefinition = {
  id: string;
  title: string;
  slug: string;
  scope?: string; // parsed from "Scope: <area>" metadata line in ticket doc
  ticketFile: string;
};
```

**2. `planning.ts` — parse `Scope:` line**

In the ticket-parsing logic, scan the ticket markdown for a line matching `/^Scope:\s*(.+)$/m` and populate `TicketDefinition.scope` with the trimmed value.

**3. `pr-metadata.ts` — rewrite `buildPullRequestTitle`**

Remove `commitSubject` parameter. Derive type and scope from ticket fields:

```ts
export function buildPullRequestTitle(
  ticket: Pick<TicketState, 'id' | 'title' | 'ticketFile' | 'scope'>,
): string {
  const typeMatch = basename(ticket.ticketFile).match(/^ticket-\d+-([a-z]+)-/);
  const type = typeMatch?.[1] ?? 'feat';
  const scopePart = ticket.scope ? `(${ticket.scope})` : '';
  const subject = ticket.title.toLowerCase();
  return `${type}${scopePart}: ${subject} [${ticket.id}]`;
}
```

**4. `ticket-flow.ts` — remove `readFirstCommitSubject` from `openPullRequest` call**

At line ~521, replace:

```ts
dependencies.buildPullRequestTitle(
  target,
  dependencies.readFirstCommitSubject(target.worktreePath, target.baseBranch),
);
```

With:

```ts
dependencies.buildPullRequestTitle(target);
```

Remove `readFirstCommitSubject` from the `dependencies` type for `openPullRequest` if it is no longer used elsewhere.

**5. `ticket.template.md` — add optional `Scope:` line**

Add `Scope: <codebase-area>  (optional — omit if scope is unclear)` below the `Size:` line.

## Refactor

- Remove the `isConventionalCommitSubject` function and `commitSubject` stripping regexes from `pr-metadata.ts` if they are no longer referenced after the signature change
- Update existing `buildPullRequestTitle` tests in `orchestrator.test.ts` to use the new signature

## Review Focus

- `basename(ticket.ticketFile)` must handle both relative and absolute paths — use Node's `basename` from `path`
- Confirm `readFirstCommitSubject` is not used by any other call site before removing it from the dependencies type
- The `Scope:` parse must be case-insensitive and trim whitespace: `Scope:  CLI ` → `cli` (or preserve casing? decide and document)
- For tickets that build a client-side helper constructing an API URL: verify the server-side handler reads and uses the params that `<helper>` sends — check both sides of the boundary, not just each in isolation.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `buildPullRequestTitle({ ticketFile: 'ticket-01-fix-state-sync.md', scope: 'cli', id: 'P1.01', ... })` produced `feat: ...` instead of `fix(cli): ...` — the old implementation ignored ticketFile and scope entirely.
Why this path: regex on basename is the smallest change that removes commit-order dependency without touching state hydration; readFileSync in parsePlan keeps scope loading co-located with ticket file path construction.
Alternative considered: async parsePlan with `readFile` — rejected because it would require propagating async through cli-runner callers and is more surface area than needed.
Deferred: removing `readFirstCommitSubject` from platform.ts and platform-adapters.ts (still referenced by the platform interface; opportunistic cleanup deferred to Phase 02).
