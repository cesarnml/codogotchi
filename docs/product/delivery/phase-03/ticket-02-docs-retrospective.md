# P3.02 Docs update and retrospective

Size: 1 point
Scope: docs

## Outcome

- `docs/template/delivery/delivery-orchestrator.md` documents the worktree guard (exempt/guarded split), `status` one-command output format, doc-only early failure behavior at `post-verify`, and phase-complete signal in `advance`
- `docs/template/overview/start-here.md` reflects the new `status` output format
- Phase 03 retrospective written at `notes/public/phase-03-orchestrator-ergonomics-retrospective.md` using `.agents/skills/write-retrospective/SKILL.md`

## Red

Doc-only ticket — no failing test. Instead, assert the docs contain the new content before committing:

- Confirm `delivery-orchestrator.md` mentions the worktree guard exempt list (`status`, `sync`, `start`)
- Confirm `delivery-orchestrator.md` documents the `status` one-command format
- Confirm `start-here.md` `status` entry reflects the new format

Commit:

```
docs(P3.02): orchestrator ergonomics docs and phase-03 retrospective [P3.02]
```

## Green

**`docs/template/delivery/delivery-orchestrator.md`:**

- In the `## Commands` section, add a `Worktree guard` subsection noting:
  - Commands exempt from worktree guard: `status`, `sync`, `start`
  - All other commands require execution from the active ticket's worktreePath
  - Error format: `Error: You are in <cwd>. Run: cd <worktreePath> && bun run deliver --plan <plan> <command>`
- Update the `status` command description to document the one-command output format:
  ```
  Active ticket: <id> — <title>
  Status: <state>
  Next command: bun run deliver --plan <path> <next-command>
  ```
  And the phase-complete variant:
  ```
  Phase complete. Awaiting developer review.
  ```
- In the `post-verify` command description, document the doc-only early failure: "When run on a doc-only ticket with no commits on the branch, fails immediately with a clear error rather than advancing to `open-pr`."
- In the `advance` command description, document the phase-complete signal: "When the final ticket goes `done`, prints 'Phase complete. Awaiting developer review.' — no next command. Cook-mode agent self-terminates; gated-mode stop was already in effect."

**`docs/template/overview/start-here.md`:**

- Update the `status` one-liner to reflect the new output format: `# shows active ticket, current status, and one next command`

**Phase 03 retrospective:**

- Read `.agents/skills/write-retrospective/SKILL.md` for section structure and output conventions
- Write retrospective to `notes/public/phase-03-orchestrator-ergonomics-retrospective.md`
- Retrospective trigger per implementation plan: after first full phase delivery on `pirate-claw` or `coding-stats` — if that delivery has not yet happened, write a provisional retrospective noting the trigger condition and what was shipped; update after consumer use

## Refactor

None — doc-only ticket.

## Review Focus

- Zero `.ts` files changed — this is a doc-only ticket; any code change is out of scope
- `delivery-orchestrator.md` worktree guard section accurately reflects the exempt list in code (`status`, `sync`, `start`)
- The `status` output format documented matches what `formatStatus` actually outputs after P3.01

## Rationale

Red first: Confirmed `delivery-orchestrator.md` contained no mention of "worktree guard", "exempt", or "status" one-command format before implementation. `start-here.md` status comment was generic (`# show current state`), not format-specific.

Why this path: Worktree guard and `status` format documentation added as named subsections under `## Commands` so agents re-reading the orchestrator doc get the new behavior as part of the command reference, not buried in a separate doc section. Retrospective written as a provisional artifact per the implementation plan trigger condition — first consumer-repo delivery will validate the Phase 03 hypothesis.

Alternative considered: Adding the worktree guard documentation under `## What It Owns` rather than as a `## Commands` subsection. Rejected because the exempt/guarded split is command-invocation behavior, not ownership scope — it belongs alongside the command list.

Deferred: Surfacing `ai-code-review` skill absence as a warning at `open-pr` time (currently an ENOENT error at `poll-review`). Noted in retrospective follow-up for Phase 04 consideration.
