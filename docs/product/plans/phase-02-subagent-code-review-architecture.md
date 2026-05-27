# Phase 02: subagentCodeReview Architecture

**Delivery status:** Tickets approved — `docs/product/delivery/phase-02/` implementation plan committed to main.

## TL;DR

**Goal:** Replace the low-value `selfAudit` + `codexPreflight` duality with a single, agent-agnostic `subagentCodeReview` step that structurally eliminates self-review bias by context-isolating the reviewer.

**Ships:**

- `subagentCodeReview` step: execution agent spawns a context-isolated subagent of the same type to review the diff against the ticket's `## Review Focus` and patch what it finds
- `reviewSubagentOverride` config key: when present, overrides the default same-type subagent (Claude→`codex:codex-rescue` is the only supported cross-agent pairing today)
- Renamed CLI command: `post-verify` replaces `post-verify-self-audit`; `subagent-code-review` replaces `codex-preflight`
- Updated state.json fields and ticket status progression reflecting the new step
- `fetch_ai_pr_comments.sh` made data-driven: reads `ai_review_agents` from `orchestrator.config.json` via `jq` instead of hardcoded login patterns
- Hard startup error if `selfAudit` or `codexPreflight` keys are present in any config

**Defers:**

- Consumer repo config updates (`pirate-claw`, `coding-stats`) — handled separately via `/soa update` when the operator is ready
- Support for additional cross-agent pairings beyond Claude→`codex:codex-rescue`
- Subagent reachability validation at startup

---

The `selfAudit` step delivered near-zero value in practice: the execution agent, with full implementation context, consistently reported "looks good to me." `codexPreflight` patched this for Claude by invoking `codex:codex-rescue` — but that fix was Claude/Codex-specific and required explicit buy-in as a separate workflow step. The result was two config keys, two state fields, two commit suffixes, and a review architecture that only worked well for one agent family.

Phase 02 collapses this into one step with a clear contract: context isolation, not model novelty, is what eliminates bias. Any execution agent that can programmatically spawn a subagent is now a first-class participant in the review step.

## Phase Goal

This phase should leave the product in a state where:

- Any execution agent (Claude, Codex, Cursor, Copilot, etc.) that can programmatically spawn a subagent will produce real internal review value on every ticket delivery
- The orchestrator config schema has one review policy key (`subagentCodeReview`) with no vestigial `selfAudit` or `codexPreflight` keys anywhere — their presence is a hard startup error
- A commit trail with `[subagentReview]` suffix is the durable, verifiable proof that the review step ran and found something worth patching
- `fetch_ai_pr_comments.sh` detects AI reviewers from config data, not hardcoded vendor strings

## Committed Scope

### Core orchestrator changes (Ticket 1)

- Remove `selfAudit` and `codexPreflight` from `reviewPolicy`; hard startup error if either key is present
- Add `reviewPolicy.subagentCodeReview: "required" | "skip_doc_only" | "disabled"`
- Add `reviewSubagentOverride: "<subagent_type_string>"` — when absent, execution agent spawns same-type subagent; when present, overrides to the specified type (Claude→`codex:codex-rescue` is the only tested pairing)
- Rename CLI command `post-verify-self-audit` → `post-verify`; `codex-preflight` → `subagent-code-review`
- State.json: remove `selfAuditOutcome`, `selfAuditCompletedAt`, `selfAuditPatchCommits`, `codexPreflightOutcome`, `codexPreflightCompletedAt`, `codexPreflightNote`, `codexPreflightPatchCommits`
- State.json: add `subagentReviewOutcome: "clean" | "patched"`, `subagentReviewCompletedAt`, `subagentReviewPatchCommits`, `subagentReviewAgent`
- Ticket status progression: remove `post_verify_self_audit_complete`, `codex_preflight_complete`; add `verified`, `subagent_review_complete`
- Full sequence: `pending → in_progress → verified → subagent_review_complete → in_review → reviewed → done`
- Commit suffix convention: `[subagentReview]` (on patch only — no commit when outcome is `"clean"`)
- Add `ai_review_agents: [{ name, login, resolve_threads }]` to config schema

### Docs + shell script (Ticket 2)

- Update `delivery-orchestrator.md`: new flow diagram, new command names, new config schema
- Add RESUME COMMAND guard to gated handoff artifact (deferred from Phase 04 — written with correct new command names)
- Add `[subagentReview]` suffix ordering note to docs
- `fetch_ai_pr_comments.sh`: remove hardcoded login patterns; read `ai_review_agents` from `orchestrator.config.json` via `jq`, build detection set from `login` fields; no vendor-specific branches

## Explicit Deferrals

- **Consumer repo config updates** (`pirate-claw`, `coding-stats`): both repos will error at startup if they pull a new orchestrator version with old config keys. Migration is deferred — the operator will handle via `/soa update` when ready. No migration path or grace period is built into this phase.
- **Cross-agent pairing beyond Claude→Codex**: `reviewSubagentOverride` schema is generic, but only one pairing is tested and supported. Other combinations are not validated or documented.
- **Startup validation of subagent reachability**: whether the configured subagent type is actually available is only knowable at step-execution time. No preflight check is added.

## Exit Condition

`delivery-orchestrator.md` documents the new flow with no references to `selfAudit` or `codexPreflight`. The orchestrator rejects any config containing those keys at startup. A Claude execution agent running `subagent-code-review` spawns `codex:codex-rescue` via `reviewSubagentOverride`, and any patch it makes is committed with `[subagentReview]`. `fetch_ai_pr_comments.sh` has no hardcoded vendor login strings. All existing tests pass; new tests cover the renamed commands and new state fields.

## Retrospective

`required` — this phase changes the internal review step for every execution agent, retires two workflow concepts (`selfAudit`, `codexPreflight`), and introduces the first cross-agent pairing hypothesis. The outcome (did `codex:codex-rescue` as a reviewer catch more real bugs than the old flow?) is a durable learning worth capturing.
