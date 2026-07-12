# Repo Rules

- If the user says `triage`, use the `soa-pr-review` skill at `.agents/skills/pr-review/SKILL.md`.
- If the user says `/soa quality-control` or `/soa qc`, use the `soa-quality-control` skill at `.agents/skills/quality-control/SKILL.md`. This is the post-phase fix-and-record lane — not a delivery-orchestrator command and not a replacement for `/soa tao` or closeout.
- For phase work, read `docs/template/overview/start-here.md` and `docs/template/delivery/delivery-orchestrator.md` first, then surface the orchestrator path before coding.
- Use the `soa-son-of-anton-ethos` skill at `.agents/skills/son-of-anton-ethos/SKILL.md` automatically when executing any approved multi-ticket phase/epic or standalone (non-ticketed) PR — including when the user says execute, begin, start, deliver, implement, continue, resume, run, drive, carry, work on, or explicitly mentions `son of anton` / `son-of-anton ethos`. That skill owns execution mechanics, stop conditions, polling, and review outcome recording.
- For new product feature-set expansion, phase shaping, or epic decomposition: run a planning pass and use `soa-grill-me` before accepting any plan. Developer approval of ticket decomposition is required before implementation.
- Prefer `bun run deliver --plan ...` over ad hoc implementation. The delivery orchestrator reads `orchestrator.config.json` at repo root; see `docs/template/delivery/delivery-orchestrator.md`. For orchestrated ticket work, the handoff under `.agents/delivery/<plan-key>/handoffs/` is required input alongside plan and ticket docs.
- New product phase/epic starts only after developer-approved ticket decomposition. Docs-only, cleanup-only, and tooling-only changes skip this. Smaller bounded changes may ship as standalone PRs using the orchestrator's `triage-standalone` path.
- Final merge of stacked PR slices requires developer approval. Close completed phases with `bun run closeout-stack --plan <plan-path>`.
- PR titles: Conventional-Commit-style subject + active ticket suffix (e.g. `[P3.02]`) when the ticket is clear from branch/docs/diff. Apply even when the user did not type `pr`.

## Subagent Review Rules

When invoking a review subagent during orchestrated delivery:

- **Preferred-runner:** pass `--subagent <claude-cli|codex-cli|cursor-cli>` to `subagent-review`. The CLI tries the preferred runner first, then the other programmatic runners, then records an honest `skipped` if none are available. No config changes needed when switching agent platforms.
- **Adversarial prompt required:** the subagent prompt must assume the implementation has holes and find them. Do not rationalize away anything you notice — flag it and let the human decide. A checklist of "did the ticket spec land?" is not a review.
- **No rationalizing away findings:** the subagent must not suppress or downplay what it finds. Flag everything; the human decides what to act on.

## Pre-Commit

Before committing: run `bun run format` **first**, then stage, then commit.
Current commands: `bun run format`, `bun run verify`, `bun run verify:quiet`, `bun run ci`, `bun run ci:quiet`.

**Orchestrator-written artifacts must be formatted before staging.** Files written by `bun run deliver` commands (review JSON, triage JSON, state files, handoffs) never pass through the editor and bypass format-on-save. If you stage and commit them before running format, the next CI run reformats them and leaves a trivially-dirty working tree. The fix is always: run format → stage → commit, in that order.

## Ticket Completion Checklist

Before closing a delivery ticket:

- Add/update `## Rationale` in the ticket doc when behavior or trade-offs changed; append later findings there — not in PR bodies or chat.
- Check `README.md` when user-visible behavior, commands, or project status changed.
- Check `docs/template/overview/start-here.md` when delivered scope, commands, status, or deferrals changed.
- Verify the relevant tests or checks for the completed work.

## On Phase or Epic Completion

Write `docs/product/retrospectives/<plan-path>-retrospective.md` using the `soa-write-retrospective` skill at `.agents/skills/write-retrospective/SKILL.md` for section structure and placement conventions.
