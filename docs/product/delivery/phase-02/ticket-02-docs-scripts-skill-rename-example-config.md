# P2.02 Docs, shell scripts, skill rename, example config

Size: 3 points
Scope: docs/template/delivery, .agents/skills

## Outcome

- `docs/template/delivery/delivery-orchestrator.md` updated: new flow diagram (`pending → in_progress → verified → subagent_review_complete → in_review → reviewed → done`), new command names (`post-verify`, `subagent-review`), new config schema (`subagentReview`, `prReview`, `reviewSubagentOverride`, `prReviewAgents`), `[subagentReview]` commit suffix note, zero references to `selfAudit`/`codexPreflight`/`codex-preflight`/`post-verify-self-audit`
- RESUME COMMAND guard added to gated handoff artifact generation in `ticket-flow.ts` (carried from Phase 01 deferrals) — uses correct new command names
- `.agents/skills/ai-code-review/` directory renamed to `.agents/skills/pr-review/`
- `fetch_ai_pr_comments.sh` renamed to `fetch_pr_review_comments.sh`; login detection made data-driven: remove `looks_like_supported_ai_identity` hardcoded regex and `vendor_name` hardcoded login branches; read `prReviewAgents` from `orchestrator.config.json` via `jq`; build login-to-vendor lookup from config data; exit 0 with empty-result JSON when `reviewPolicy.prReview == "disabled"`
- `triage_ai_review.sh` renamed to `triage_pr_review.sh`
- `orchestrator.config.post-phase-02.example.json` created at repo root: complete post-phase-02 config reproducing old coderabbit + qodo hardcoded behavior as `prReviewAgents` data, with `reviewSubagentOverride: "codex:codex-rescue"` for Claude environments
- All skill files referencing old command names updated: `soa/SKILL.md`, `son-of-anton-ethos/SKILL.md`, `closeout-stack/SKILL.md`, `ai-code-review/SKILL.md` (now `pr-review/SKILL.md`), `.claude/skills/soa/SKILL.md`
- `sync-skills.sh` updated if it references the old skill directory name

## Red

- Add test (or grep assertion in CI): `delivery-orchestrator.md` contains no occurrences of `selfAudit`, `codexPreflight`, `codex-preflight`, `post-verify-self-audit`
- Add test: handoff artifact for a gated ticket contains a `## RESUME COMMAND` section with the correct `bun run deliver` invocation
- Run `bun test` — confirm RESUME COMMAND test fails (not yet implemented)
- Commit with suffix `[red]`: `test(P2.02): docs clean and resume command in handoff [red]`

## Green

- `delivery-orchestrator.md`: rewrite flow diagram section, command reference entries for `post-verify` and `subagent-review`, config schema section; remove all old references
- `ticket-flow.ts`: add RESUME COMMAND block to gated handoff artifact — format: `## RESUME COMMAND\n\`bun run deliver --plan <planPath> subagent-review\``(or`open-pr`depending on state position); guard fires only in`gated` boundary mode
- Rename `.agents/skills/ai-code-review/` → `.agents/skills/pr-review/` via `git mv`
- Rename script files via `git mv`
- `fetch_pr_review_comments.sh`: replace `looks_like_supported_ai_identity` function body with `jq`-based login set built from `(.prReviewAgents // []) | map(.login) | map(ascii_downcase)`; replace `vendor_name` hardcoded login branches with a dynamic lookup against the same set (map login → name from config); add early-exit block: read `reviewPolicy.prReview` from config, if `"disabled"` print empty result JSON and exit 0
- `triage_pr_review.sh`: rename only (no logic changes)
- `orchestrator.config.post-phase-02.example.json`: create with coderabbit + qodo entries matching old hardcoded logins; include `reviewSubagentOverride` and `subagentReview`/`prReview` keys
- Update all skill `.md` files referencing old command names
- Update `sync-skills.sh` if needed

## Refactor

- Remove any dead comment blocks in `fetch_pr_review_comments.sh` that described the old hardcoded detection approach

## Review Focus

- `fetch_pr_review_comments.sh` login detection: verify the new `jq` path produces the same detection behavior as the old hardcoded regex for coderabbit (`coderabbitai`), qodo (`qodo-merge`), greptile, sonarqube — the example config is the test vector
- Early-exit path: confirm empty-result JSON has the correct shape (`{"agents":[],"detected":false,"vendors":[],"comments":[]}`) so the orchestrator's fetch consumer doesn't error on missing keys
- RESUME COMMAND guard: confirm it only appears in gated mode handoffs, not cook or glide
- `delivery-orchestrator.md`: grep for `selfAudit`, `codexPreflight`, `codex-preflight`, `post-verify-self-audit` — must be zero matches
- `orchestrator.config.post-phase-02.example.json`: verify `prReviewAgents` logins match the old hardcoded values exactly so existing deployments can migrate by copy-paste

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.
