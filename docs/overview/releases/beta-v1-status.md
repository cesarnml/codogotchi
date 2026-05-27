# Beta v1 — What Actually Shipped

This document describes the current state of Son of Anton as of private beta launch (2026-05-14).
It corrects the record where Phase 10's retrospective describes the pre-refactor API, and captures
post-phase patches that shipped directly to `main` without their own phase tickets.

---

## What the Phase 10 Retrospective Describes vs What Shipped

Phase 10 shipped PRs [#33–#37](https://github.com/cesarnml/son-of-anton/pulls). Those PRs introduced
a `subagentReviewRunner` config field and `--runner-subagent-review` CLI flag. That design was retired
immediately after phase close as part of a pre-beta clean-break refactor. The retrospective describes
the intermediate state; the code no longer matches it.

### The clean-break refactor (post-P10, pre-beta)

The `subagentReviewRunner` / `reviewSubagentOverride` / `--runner-subagent-review` API surface was
replaced with a single `--preferred-runner <claude-cli|codex-exec>` flag on `execute` and `resume`.

**Before:** runner identity was declared in `orchestrator.config.json` (`subagentReviewRunner`) or
carried through `runPolicy` (`runner` variant of `RunPolicyReviewSubagent`). Config-level declaration
meant the runner had to be known at plan time.

**After:** `--preferred-runner` is an invocation-time flag. The orchestrator tries the preferred runner,
falls back to the other runner, then honestly skips if neither succeeds. Outcome is determined by
`git status --porcelain` after the runner exits — no separate proof artifact path needed for the skip
case.

The `SubagentRunnerArtifact` JSON proof artifact is still written when a runner completes. The
`validateRunnerArtifact` function is still the structural gate on `open-pr`. The only change is how
runner identity is communicated — flag instead of config key.

### What `orchestrator.config.json` looks like now

```json
{
  "defaultBranch": "main",
  "planRoot": "docs",
  "runtime": "bun",
  "packageManager": "bun",
  "ticketBoundaryMode": "cook",
  "reviewPolicy": {
    "subagentReview": "skip_doc_only",
    "prReview": "disabled"
  }
}
```

No runner field. Runner selection happens at `execute` / `resume` time via `--preferred-runner`.

---

## Boundary Modes: `cook` and `gated` Only

`glide` appeared in Phase 7 as a placeholder for a future "host-driven self-reset" mode that was
never implemented. It fell back silently to `gated` in all code paths. It has been removed from
the codebase and docs as of this beta.

Supported modes:

- **`cook`** — `advance` auto-starts the next ticket immediately. Recommended for trusted agents.
- **`gated`** — `advance` stops and prints the canonical resume prompt. Start here.

---

## Known Gaps at Beta Launch

### `validateRunnerArtifact` accepted empty strings (now fixed)

The validator checked `typeof value === 'string'` but not `value !== ''`. A `reviewedHeadSha: ""`
would pass structural validation. Fixed in this pre-beta patch: both `reviewedHeadSha` and
`completedAt` now reject the empty string.

### `post-red` placement and skip metadata are explicit

The `post-red` command now runs before implementation on code tickets: write the failing behavior
test, commit it with a `[red]` suffix, then record it with `post-red`. Tickets with no testable
behavior declare `Red: skip` in metadata, and doc-only branches skip the gate structurally. The
temporary `--red-commit-sha` recovery idea was removed rather than shipped.

### No mid-phase `/soa update` path defined

Updating the son-of-anton subtree while a phase is in flight (open worktrees, mid-stack PRs) is
undefined. The mechanics are sound — subtree pull and sync are independent of worktree state — but
the implications for in-flight handoffs and agent-rule injection haven't been tested or documented.
Until this is defined, the recommendation is: complete or park the active phase before updating.

### `soa-sync.sh` consumer-mode features don't run in the source repo

`bun run sync` in the son-of-anton repo itself runs in source mode (skills relink only). Consumer
features — `orchestrator.config.json` scaffold, AGENTS.md/CLAUDE.md injection, global skill refresh,
migration runner — only fire when `.son-of-anton/` exists (consumer mode). This is correct behavior,
not a bug. It means the source repo can't exercise the full install path end-to-end; that path is tested through
consuming repos (`coding-stats`, `pirate_claw`).

---

## What Was Verified Pre-Beta

- Full install path via `git subtree add` + `soa-sync.sh` in a greenfield repo (coding-stats).
- `orchestrator.config.json` auto-scaffold with lock-file-aware `packageManager` detection.
- AGENTS.md and CLAUDE.md injection via `<!-- soa:start -->` / `<!-- soa:end -->` markers.
- Skill symlinks under `.claude/skills/soa*`.
- Global skill refresh (`~/.claude/skills/soa/SKILL.md`) when previously installed.
- Full phase delivery through the ticket loop in `cook` mode (phases 1–10).
- `gated` boundary mode with resume prompt output.
- `--preferred-runner claude-cli` and `codex-exec` fallback chain.
- `validateRunnerArtifact` rejection of structurally degenerate artifacts (empty-string fields now included).
- `skip_doc_only` policy correctly auto-skipping review stages on doc-only tickets.

---

## Consuming Repo State at Beta Launch

| Repo           | Subtree version | Outstanding phases | Notes                                                      |
| -------------- | --------------- | ------------------ | ---------------------------------------------------------- |
| `coding-stats` | current (main)  | none               | Updated to beta; injection and config verified             |
| `pirate_claw`  | current (main)  | phase in flight    | Stale `reviewSubagentOverride` rule removed; sync deferred |

---

## Updates since beta

- **Programmatic runners (2026-05):** `subagent-review` supports `claude-cli`, `codex-cli`, and `cursor-cli` via `--subagent` / `orchestrator.config.json:subagentRunner`. The Phase 10-era `--preferred-runner` name is gone; fallback tries all three programmatic runners before an honest `skipped`. See `docs/template/delivery/delivery-orchestrator.md` (Programmatic subagent runners).
