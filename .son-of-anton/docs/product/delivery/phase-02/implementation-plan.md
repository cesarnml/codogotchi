# Phase 02 — subagentReview Architecture

> Replace the `selfAudit` + `codexPreflight` duality with a single `subagentReview` step and make PR review agent detection data-driven.

## Epic

[docs/product/plans/phase-02-subagent-code-review-architecture.md](../../plans/phase-02-subagent-code-review-architecture.md)

## Product contract

After this phase ships:

- Any execution agent that can spawn a subagent gets real internal review value on every ticket delivery via `subagent-review` — one CLI command, one state field, one commit suffix
- `orchestrator.config.json` with `selfAudit` or `codexPreflight` keys hard-errors at startup — no silent misconfiguration
- PR review bot detection reads `prReviewAgents[].login` from config, not hardcoded vendor strings in shell scripts
- The `ai-code-review` skill is renamed `pr-review` and its scripts renamed to match

## Grill-Me decisions locked

- **`reviewSubagentOverride` is top-level** → not nested in `reviewPolicy`; it's a routing decision, not a stage toggle; matches `ticketBoundaryMode` precedent
- **Hard startup error at `parseReviewPolicy` (parse time)** → `selfAudit`/`codexPreflight` presence errors immediately, before any command runs; consistent with unknown-key guard already in `parseReviewPolicy`
- **`prReviewAgents` top-level in `orchestrator.config.json`** → validated at load time when `prReview !== "disabled"`; shell script reads same file via `jq`; no separate file
- **`reviewPolicy.externalReview` → `reviewPolicy.prReview`** → lifecycle position (`prReview` = post-PR external bots) is the right discriminator, not "external"
- **Login detection data-driven; comment-kind classification stays per-vendor hardcoded** → `looks_like_supported_ai_identity` + `vendor_name` login regex becomes a `jq` build from config; kind-classification branches (coderabbit summary logic, qodo body parsing, greptile SHA match) are not genericizable without breaking accuracy
- **Two tickets; ticket 2 includes shell scripts + skill rename + docs + example config** → shell script change is ~5 lines, only meaningful after ticket 1 ships the schema; no conflicting files between doc and script areas
- **`subagentReview` not `subagentCodeReview`** → "code" adds no information in a system where every review is a code review; shorter is clearer
- **`subagent-review` is record-only (Option A)** → agent spawns subagent out-of-band, calls `bun run deliver ... subagent-review [clean|patched] [shas]` to record; identical contract to `post-verify`
- **All tests migrated in ticket 1** → old status strings and state fields are removed, not deprecated; TypeScript type errors catch any misses automatically; no deferred cleanup

## Ticket Order

1. `P2.01 Core orchestrator: schema, CLI, state machine, tests`
2. `P2.02 Docs, shell scripts, skill rename, example config`

## Ticket Files

- `ticket-01-core-orchestrator-schema-cli-state.md`
- `ticket-02-docs-scripts-skill-rename-example-config.md`

## Exit Condition

`delivery-orchestrator.md` documents the new flow with zero references to `selfAudit`, `codexPreflight`, `codex-preflight`, or `post-verify-self-audit`. The orchestrator rejects any config containing those keys at startup. `subagent-review clean|patched [shas]` records the outcome and transitions state. `fetch_pr_review_comments.sh` has no hardcoded vendor login strings. The `ai-code-review` skill directory is renamed `pr-review`. All existing tests pass; new tests cover renamed commands and new state fields.

## CI Baseline

> Baseline recorded: 2026-05-05 — 172 pass, 0 fail (bun test, 11 files, 390 expect() calls)

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** do not block a ticket; newly introduced failures do.
- Ticket 2 must not reference any old command names — reviewer should grep for `selfAudit`, `codexPreflight`, `codex-preflight`, `post-verify-self-audit` across all changed files.

## Explicit Deferrals

- Consumer repo config updates (`pirate-claw`, `coding-stats`) — handled via `/soa update` when the operator is ready; those repos will hard-error at startup until migrated
- Cross-agent pairing beyond Claude→`codex:codex-rescue` — `reviewSubagentOverride` schema is generic but only one pairing is tested
- Subagent reachability validation at startup — only knowable at step-execution time
- Comment-kind classification genericization — per-vendor `comment_kind` logic stays hardcoded; only login detection becomes data-driven

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- TypeScript type errors from removed fields that cascade into unexpected areas — pause and assess scope before continuing.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Changes the internal review step for every execution agent, retires two workflow concepts (`selfAudit`, `codexPreflight`), and introduces the first cross-agent pairing hypothesis. Outcome is a durable learning worth capturing.
Trigger: Developer approval of final PR merge.
Artifact: `notes/public/phase-02-retrospective.md`
