## Son-of-Anton Skill Triggers

Use these skills when working in a consumer repo that has installed Son-of-Anton
via `git subtree add --prefix .son-of-anton`.

- **`soa`** — canonical entrypoint for all SoA commands. Invoke via `Skill` tool with `skill: "soa"` and args such as `plan`, `decompose`, `execute`, `resume`, `triage-ticket`, or `triage-standalone`. Skill: `.son-of-anton/.agents/skills/soa/SKILL.md`.
- **`soa-son-of-anton-ethos`** — invoke automatically whenever the user executes, begins, starts, delivers, implements, continues, resumes, runs, drives, carries, or works on any approved multi-ticket phase/epic or standalone PR. This skill owns execution mechanics, stop conditions, polling, and review outcome recording. Skill: `.son-of-anton/.agents/skills/son-of-anton-ethos/SKILL.md`.
- **`soa-pr-review`** — invoke when the user says `triage`. Triages AI-generated PR review comments. Skill: `.son-of-anton/.agents/skills/pr-review/SKILL.md`.
- **`soa-grill-me`** — invoke before accepting any plan or ticket decomposition. Stress-tests assumptions. Skill: `.son-of-anton/.agents/skills/grill-me/SKILL.md`.
- **`soa-closeout-stack`** — squash-merges completed stacked PRs onto main. Only invoked with explicit developer approval. Skill: `.son-of-anton/.agents/skills/closeout-stack/SKILL.md`.
- **`soa-enter-worktree`** — bootstraps a fresh git worktree with deps and env before starting ticket implementation. Skill: `.son-of-anton/.agents/skills/enter-worktree/SKILL.md`.
- **`soa-write-retrospective`** — writes phase or epic retrospectives to `docs/product/retrospectives/`. Skill: `.son-of-anton/.agents/skills/write-retrospective/SKILL.md`.

## Subagent Review Rules

When invoking a review subagent during orchestrated delivery:

- **Preferred-runner:** pass `--subagent <claude-cli|codex-cli|cursor-cli>` to `subagent-review`. The CLI tries the preferred runner first, then the other programmatic runners, then records an honest `skipped` if none are available. No config changes needed when switching agent platforms.
- **Adversarial prompt required:** assume the implementation has holes. Do not rationalize away anything you notice — flag it and let the human decide. A "did the spec land?" checklist is not a review.
- **No rationalizing findings:** report everything you find. The human decides what to act on.

## .son-of-anton Subtree — Never Edit Directly

**Do not modify any file inside `.son-of-anton/` in this repo.** It is a read-only git subtree pulled from `cesarnml/son-of-anton`. Direct edits will not propagate to other consumer repos and will be overwritten on the next `/soa update`.

- SoA tooling changes belong in `cesarnml/son-of-anton`. Upstream first, then pull via `/soa update`.
- If you spot a needed change inside `.son-of-anton/`, stop and tell the developer — do not patch in place.

## Pre-Commit

**Prerequisite:** Son-of-Anton requires a global `bun` install. All CLI delivery commands run via `bun run deliver …`.

Before committing: run `bun run format` **first**, then stage, then commit. Use `bun run verify` (or `bun run verify:quiet`) and `bun run ci:quiet` as the final publication gate before opening a PR.

**Orchestrator-written artifacts must be formatted before staging.** Files written by `bun run deliver` commands (review JSON, triage JSON, state files, handoffs) never pass through the editor and bypass format-on-save. Stage and commit them before running format and the next CI run will reformat them, leaving a trivially-dirty working tree. Always: format → stage → commit.
