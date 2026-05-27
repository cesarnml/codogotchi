# P2.01 Core orchestrator: schema, CLI, state machine, tests

Size: 5 points
Scope: tools/delivery

## Outcome

- `orchestrator.config.json` with `selfAudit` or `codexPreflight` in `reviewPolicy` throws a hard error at parse time — no command proceeds
- `reviewPolicy.subagentReview` and `reviewPolicy.prReview` are valid stage toggles (`"required" | "skip_doc_only" | "disabled"`)
- `reviewPolicy.externalReview` is removed; `reviewPolicy.prReview` replaces it
- Top-level `reviewSubagentOverride?: string` accepted and passed through by the config loader
- Top-level `prReviewAgents?: [{name: string, login: string, resolveThreads: boolean}]` validated at load time when `reviewPolicy.prReview !== "disabled"`; ignored when `"disabled"`
- CLI `post-verify-self-audit` is renamed `post-verify`; `internal-review` deprecation alias removed
- CLI `codex-preflight` is renamed `subagent-review` with the same record-only contract: `subagent-review [ticket-id] [clean|patched] [patch-commit-sha ...]`
- `TicketStatus` no longer contains `post_verify_self_audit_complete` or `codex_preflight_complete`; contains `verified` (replaces `post_verify_self_audit_complete`) and `subagent_review_complete` (replaces `codex_preflight_complete`)
- `TicketState` no longer contains `postVerifySelfAuditCompletedAt`, `selfAuditOutcome`, `selfAuditPatchCommits`, `codexPreflightOutcome`, `codexPreflightCompletedAt`, `codexPreflightNote`, `codexPreflightPatchCommits`; contains `subagentReviewOutcome`, `subagentReviewCompletedAt`, `subagentReviewPatchCommits`, `subagentReviewAgent`
- `format.ts` `review_policy=` line reflects new keys; ticket status formatting reflects new fields
- Ticket status flow in `ticket-flow.ts`: `pending → in_progress → verified → subagent_review_complete → in_review → reviewed → done`
- Handoff artifact uses new command names throughout
- `orchestrator.config.json` at repo root updated: `selfAudit`/`codexPreflight` removed, `subagentReview`/`prReview` added
- All 172 existing tests migrated to new field names and status strings — `bun test` green at PR open
- New tests: hard startup error for `selfAudit`/`codexPreflight` presence; `subagentReview` state transitions; `prReviewAgents` load-time validation

## Red

- Add test: `loadOrchestratorConfig` with `reviewPolicy: { selfAudit: "disabled" }` → throws with message containing `"selfAudit"`
- Add test: `loadOrchestratorConfig` with `reviewPolicy: { codexPreflight: "disabled" }` → throws with message containing `"codexPreflight"`
- Add test: `loadOrchestratorConfig` with `reviewPolicy: { prReview: "required" }` and no `prReviewAgents` → throws at load time
- Add test: `loadOrchestratorConfig` with `reviewPolicy: { prReview: "disabled" }` and no `prReviewAgents` → succeeds
- Add test: ticket status transition `in_progress → verified` via `post-verify`
- Add test: ticket status transition `verified → subagent_review_complete` via `subagent-review`
- Run `bun test` — confirm new tests fail; confirm existing tests that reference old field names now fail TypeScript compilation
- Commit with suffix `[red]`: `test(P2.01): subagentReview schema and state machine [red]`

## Green

- `config.ts`: update `KNOWN_KEYS` in `parseReviewPolicy` to `['subagentReview', 'prReview', 'externalReview']`; add presence check before unknown-key guard that throws for `selfAudit` and `codexPreflight`; add `subagentReview` and `prReview` to `ReviewPolicy`/`ResolvedReviewPolicy`; add `reviewSubagentOverride` and `prReviewAgents` to config types and loader; add `parsePrReviewAgents` validation function; skip `prReviewAgents` validation when `prReview === "disabled"`
- `types.ts`: update `TicketStatus` union; update `TicketState` fields as specified in Outcome above; remove `CodexPreflightOutcome` type
- `ticket-flow.ts`: update all status guards and transitions; update handoff `requiredReads` and instruction text to use `post-verify` and `subagent-review`
- `cli.ts`: update usage string
- `cli-runner.ts`: rename command dispatch cases; remove `internal-review` alias
- `format.ts`: update `review_policy=` line and ticket status block
- `orchestrator.config.json`: replace `selfAudit`/`codexPreflight` with `subagentReview`/`prReview`
- Migrate all test fixtures: replace `post_verify_self_audit_complete` → `verified`, `codex_preflight_complete` → `subagent_review_complete`; replace all removed state fields with new equivalents; update any `review_policy=` string assertions

## Refactor

- Rename internal variables/constants that reference `selfAudit` or `codexPreflight` for consistency — only within files already touched

## Review Focus

- `parseReviewPolicy` hard-error path: confirm it fires for `selfAudit`/`codexPreflight` presence, not just unknown keys (they must be caught before the unknown-key loop, or the error message must be distinct)
- `prReviewAgents` validation: confirm `login` and `name` are required strings; `resolveThreads` defaults to `false` if absent rather than hard-erroring
- Status transition guards in `ticket-flow.ts`: verify `post-verify` requires `in_progress` → `verified` and `subagent-review` requires `verified` → `subagent_review_complete` — no short-circuiting
- `orchestrator.config.json` at repo root: confirm `selfAudit`/`codexPreflight` are fully gone
- Test coverage: at least one test per new config key (presence error, valid value, boundary default); at least one test per new status transition

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.
