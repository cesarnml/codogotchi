<!-- soa:start -->

## Son-of-Anton Skill Triggers

Use these skills when working in a consumer repo that has installed Son-of-Anton
via `git subtree add --prefix .son-of-anton`.

- **`soa`** — canonical entrypoint: `/soa plan`, `/soa decompose`, `/soa execute`, `/soa resume`, `/soa triage-ticket`, `/soa triage-standalone`. Skill at `.son-of-anton/.agents/skills/soa/SKILL.md`.
- **`soa-son-of-anton-ethos`** — invoke automatically for any approved multi-ticket phase/epic or standalone PR delivery. Trigger keywords: execute, begin, start, deliver, implement, continue, resume, run, drive, carry, work on, or explicit mention of `son of anton`. Skill at `.son-of-anton/.agents/skills/son-of-anton-ethos/SKILL.md`.
- **`soa-pr-review`** — triage AI-generated PR review comments. Trigger: user says `triage`. Skill at `.son-of-anton/.agents/skills/pr-review/SKILL.md`.
- **`soa-grill-me`** — stress-test a plan before accepting it. Use before any plan or ticket decomposition is finalized. Skill at `.son-of-anton/.agents/skills/grill-me/SKILL.md`.
- **`soa-closeout-stack`** — squash-merge completed stacked PRs onto main after developer approval. Skill at `.son-of-anton/.agents/skills/closeout-stack/SKILL.md`.
- **`soa-enter-worktree`** — bootstrap a fresh git worktree with deps and env before starting ticket work. Skill at `.son-of-anton/.agents/skills/enter-worktree/SKILL.md`.
- **`soa-write-retrospective`** — write a phase or epic retrospective to `docs/product/retrospectives/`. Skill at `.son-of-anton/.agents/skills/write-retrospective/SKILL.md`.

## Subagent Review Rules

When invoking a review subagent during orchestrated delivery:

- **Subagent selection:** pass `--subagent <claude-cli|codex-cli|cursor-cli>` to `subagent-review`, or set `subagentRunner` in `orchestrator.config.json`. The CLI tries the preferred runner first, then the other programmatic runners, then records an honest `skipped` if none are available. Missing both is a hard error — SoA ships no silent default.
- **Reconciliation:** run `reconcile-subagent-review` after subagent patches and before `open-pr`. Ledger outcomes are `clean | patched | deferred | skipped`. Use `record-deferred` or `open-pr --ack-reconciliation` when consciously not patching actionable findings.
- **Adversarial prompt required:** the subagent prompt must assume the implementation has holes and find them. Do not rationalize away anything you notice — flag it and let the human decide. A checklist of "did the ticket spec land?" is not a review.
- **No rationalizing away findings:** the subagent must not suppress or downplay what it finds. Flag everything; the human decides what to act on.

## .son-of-anton Subtree — Never Edit Directly

**Do not modify any file inside `.son-of-anton/` in this repo.** It is a read-only git subtree pulled from `cesarnml/son-of-anton`. Direct edits will not propagate to other consumer repos and will be overwritten on the next `/soa update`.

- SoA tooling changes belong in `cesarnml/son-of-anton`. Upstream first, then pull via `/soa update`.
- If you spot a needed change inside `.son-of-anton/`, stop and tell the developer — do not patch in place.

## Pre-Commit Discipline

**Prerequisite:** Son-of-Anton requires a global `bun` install. All CLI delivery commands run via `bun run deliver …`.

Before committing: run `bun run format` **first**, then stage, then commit. Use `bun run verify` (or `bun run verify:quiet`) and `bun run ci:quiet` as the final publication gate before opening a PR.

**Orchestrator-written artifacts must be formatted before staging.** Files written by `bun run deliver` commands (review JSON, triage JSON, state files, handoffs) never pass through the editor and bypass format-on-save. Stage and commit them before running format and the next CI run will reformat them, leaving a trivially-dirty working tree. Always: format → stage → commit.

## Codogotchi Gate Sidecar

When `codogotchi.enabled` is not set to `false` in `orchestrator.config.json` (the default), SoA delivery commands write the current delivery gate to a global JSON sidecar at `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`). They also append each emitted gate payload to `$CODOGOTCHI_HOME/gate-transitions.log` and write durable badge context to `$CODOGOTCHI_HOME/delivery-context.json`. The codogotchi renderer reads `gate.json` to drive short-lived animation state and reads `delivery-context.json` to drive the persistent ticket/gate badges.

**Gate JSON shape:**

```json
{
  "gate": "<gate-name>",
  "since": "<ISO timestamp>",
  "expires_at": "<ISO timestamp>",
  "plan_key": "<plan-key>",
  "ticket_id": "<ticket-id>"
}
```

**Delivery context JSON shape:**

```json
{
  "owner": "soa",
  "status": "active | cleared",
  "repo_root": "<absolute-repo-root>",
  "plan_key": "<plan-key>",
  "ticket_id": "<ticket-id>",
  "last_gate": "<gate-name>",
  "updated_at": "<ISO timestamp>",
  "lease_expires_at": "<ISO timestamp>"
}
```

**Recognized gate names** (codogotchi schema-v4 ActivityState contract):
`ticket_started`, `ticket_completed`, `red_tdd`, `green_tdd`, `adversarial_review`, `open_pr`, `poll_review`, `record_review`, `review_clean`

**Key behaviors:**

- **Single global file.** `gate.json` is last-write-wins. One pet shows one current gate across all concurrent delivery runs.
- **Append-only telemetry log.** `gate-transitions.log` records every emitted gate payload as one JSON line, preserving transition order and the exact `{ since, expires_at }` window written for that emission.
- **Flat 30-second gate TTL.** `expires_at = since + 30s`. The renderer uses this only for animation expiry; persistent badges come from `delivery-context.json`.
- **Leased durable badges.** `delivery-context.json` uses `status: "active"` plus `lease_expires_at` for badge visibility. `ticket_completed` writes `status: "cleared"`, and newer hook activity from a different `source_event.repo_root` suppresses the badge immediately.
- **Emit-then-action.** Each gate is written before the delivery command's primary side effect (PR creation, polling, recording, etc.) to extend the visible animation window.
- **Best-effort.** Write failures are silently swallowed — no delivery command aborts due to a gate write error.
- **Config gate.** Setting `codogotchi.enabled: false` in `orchestrator.config.json` suppresses all writes; no `~/.codogotchi/` directory is created.
- **Explicit clear for badges.** Gate animation still expires by TTL, but persistent badges clear on `ticket_completed`, delivery-context lease expiry, or cross-repo hook activity.

**The `~/.codogotchi/` directory is global and user-scoped** — not consumer-repo-local. No `.gitignore` entry is needed.

> **Retired (as of Phase 17):** The previous `.soa/events.ndjson` NDJSON append writer is gone. Consumer repos should remove any `.soa/` gitignore entries and `soa-event-feed` references if present from Phase 15 installations.

<!-- soa:end -->
