# Phase 03: Orchestrator Ergonomics

**Delivery status:** Decomposed and delivered — `docs/product/delivery/phase-03/` exists and the phase tickets have already shipped.

## TL;DR

**Goal:** Keep a resuming agent on the orchestrator path after context compaction — so rate-limit hits, disconnects, and session resets don't end with an agent improvising outside the delivery flow.

**Ships:**

- Worktree guard: any guarded command run outside the active ticket's worktree fails immediately with the exact `cd <path> && bun run deliver ...` recovery command
- `status` next-command: always prints one unambiguous next command; prints "Phase complete. Awaiting developer review." when all tickets are `done`
- Doc-only early failure: `post-verify` fails fast when a doc-only ticket has no commits on the branch, rather than letting the failure surface at `open-pr`
- Wrong-state error UX: every state-guarded command includes current status and the valid next command in its error message
- Phase-complete signal: `advance` prints "Phase complete. Awaiting developer review." when the final ticket goes `done` (no command — signals the agent to stop, not to proceed)
- Dead code removal: `readFirstCommitSubject` removed from `platform.ts` and `platform-adapters.ts` (zero callers since Phase 01 shipped ticket-derived PR titles)

**Defers:**

- `post-red` CLI command and `red_complete` ticket status — see `notes/private/phase-04-deferred-improvements-to-soa.md`
- `reconcile-late-review` finalize path for `done` tickets — see `notes/private/phase-04-deferred-improvements-to-soa.md`
- Runtime portability / bun hardcoding for consumer repos — see `notes/private/phase-04-deferred-improvements-to-soa.md`

---

The Phase 02 retrospectives and Phase 04 gated-mode retrospective share the same failure pattern: a resumed agent reads a ticket file and improvises instead of following the orchestrator path. The root cause is not agent quality — it is that the orchestrator gives a resumed agent no strong signal about where it is, what it should do next, or why it shouldn't just start writing code. Phase 03 closes that gap without adding new architecture. All five items are UX and guard changes on top of the stable Phase 02 core. Phase 02 must be merged to main before Phase 03 delivery begins — error messages reference the Phase 02 command names (`post-verify`, `subagent-review`).

## Phase Goal

This phase should leave the product in a state where:

- A cold-start agent with only `state.json` and the plan path can run `status` and get one unambiguous command to execute next — no guessing, no file spelunking
- Any command run outside the active ticket's worktree produces a hard error with the exact recovery command, not a silent wrong-directory failure
- Any command run in the wrong ticket state tells the agent both the current state and the correct next step
- A doc-only ticket with no commits fails at `post-verify`, not at `open-pr` — the agent is told what is missing before it tries to open a PR
- A cook-mode agent that completes the final ticket receives a clear stop signal and does not go looking for a next ticket or attempt closeout autonomously
- Anton is stable enough to run unmodified on `pirate-claw` and `coding-stats` without handholding

## Committed Scope

### Worktree guard

When a guarded delivery command runs from a directory that is not the active ticket's worktree path recorded in `state.json`, fail immediately with:

```
Error: You are in <current-dir>, not the active worktree for <ticket-id>.
Run: cd <worktree-path> && bun run deliver --plan <plan> <command>
```

**Exempt commands** (safe to run from any directory):

- `status` — read-only; must work from anywhere to orient a cold-start agent
- `sync` — copies state between worktree and primary checkout; must run from primary
- `start` — creates the worktree it would need to be inside; bootstraps the flow

All other commands are guarded: `post-verify`, `subagent-review`, `open-pr`, `poll-review`, `reconcile-late-review`, `record-review`, `advance`, `restack`.

If the `worktreePath` recorded in `state.json` is stale (worktree deleted/recreated), the guard error fires the same way — the agent must re-anchor via `start` or `sync`.

### `status` next-command

`status` always prints exactly one next command. Format:

```
Active ticket: <id> — <title>
Status: <state>
Next command: bun run deliver --plan <path> <next-command>
```

When the phase is complete (all tickets `done`):

```
Phase complete. Awaiting developer review.
```

No command printed. One output, not a menu. The agent always knows what to do next or knows to stop.

### Doc-only early failure

When `post-verify` runs on a doc-only ticket and no commits exist between the ticket branch and its base, fail immediately with:

```
Error: No commits on branch for doc-only ticket <id>.
Add or update documentation files before continuing.
```

Failure is at `post-verify`, not `open-pr`. The agent is told what is missing at the earliest useful point.

### Wrong-state error UX

When any state-guarded command is run from an invalid state, the error includes the current status and the valid next command:

```
Error: `open-pr` requires status `subagent_review_complete` or `verified`. Current status: `verified`.
Next command: bun run deliver --plan <path> subagent-review
```

The agent never has to re-read docs to figure out what went wrong or what to run next.

### Phase-complete signal in `advance`

When `advance` marks the final ticket `done` and no pending tickets remain, print:

```
Phase complete. Awaiting developer review.
```

No command. This is the cook-mode stop signal — the agent reads it and ends the session. In gated mode it is academic but consistent with `status` output.

### Dead code removal

Remove `readFirstCommitSubject` from:

- `platform.ts` (export)
- `platform-adapters.ts` (interface definition and implementation)

This function has had zero callers since Phase 01 (`ticket-02-feat-pr-title`) replaced commit-derived PR titles with ticket-derived titles. No behavior change — cleanup only.

## Explicit Deferrals

- **`post-red` CLI command** — requires a new `red_complete` ticket status and new CLI command; non-trivial; own phase with own success criterion
- **`reconcile-late-review` finalize path** — post-patch recording for `done` tickets; well-scoped but separate concern from resumption ergonomics
- **Runtime portability** — bun hardcoding, `verify:quiet`/`ci:quiet` conventions for consumer repos; architectural concern, separate phase
- **Ticket template hardening** (Wave 0 items) — `## Red` section strengthening, `[subagentReview]` suffix ordering doc, cherry-pick conflict behavior doc; template-only, zero-code, can ship as a standalone PR outside the orchestrator flow at any time

## Exit Condition

Unit tests green across all five behavioral changes. Manual smoke test: from the primary checkout (`main` branch, no active worktree), run `bun run deliver --plan <any-plan> status` and confirm the output is either a single next command or "Phase complete. Awaiting developer review." with no additional noise. Consumer repos (`pirate-claw`, `coding-stats`) can pull the updated Anton subtree and run a full phase without encountering any of the five failure modes this phase fixes.

## Retrospective

`required` — the thesis is "get Anton stable enough for consumer repos without handholding." Whether Phase 03 achieves that on first real contact with `pirate-claw` or `coding-stats` is a durable learning question that feeds Phase 04 scope. Trigger: after the first full phase delivery on either consumer repo post-Phase 03 merge.
