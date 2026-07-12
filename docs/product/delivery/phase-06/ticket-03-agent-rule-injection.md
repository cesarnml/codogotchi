# P6.03 Agent-Rule Injection

Size: 3 points
Type: feat
Scope: soa-sync

## Outcome

- `AGENTS.soa.md` exists at repo root containing: skill triggers (`.son-of-anton/.agents/skills/` paths), subagent review rules, pre-commit discipline — consumer-path-correct, no source-repo commands or paths
- `CLAUDE.soa.md` exists at repo root with the same three sections in Claude-optimized language
- `soa-sync.sh` consumer mode injects each file's content into consumer `AGENTS.md` and `CLAUDE.md` via `<!-- soa:start -->` / `<!-- soa:end -->` markers; creates the target file if absent
- Re-running `bun run sync` when markers are already current produces no file mutations (idempotent upsert)
- Source-repo mode never touches `AGENTS.md` or `CLAUDE.md`
- `soa-sync.sh` consumer mode prints a lint-ignore warning line to stdout: add `.son-of-anton/` to your lint/format ignore configuration

## Red

- Write a Bun integration test in `tools/delivery/test/p6-03.test.ts`
- Fixture A (fresh consumer): `mktemp -d`, `git init`, consumer-repo layout (`.son-of-anton/` present, no `AGENTS.md`), run `soa-sync.sh`; assert `AGENTS.md` exists and contains `<!-- soa:start -->` and `<!-- soa:end -->` markers with non-empty content between them; assert same for `CLAUDE.md`; assert stdout contains lint-ignore warning
- Fixture B (idempotency): run `soa-sync.sh` again on the same fixture; assert `AGENTS.md` and `CLAUDE.md` are byte-for-byte identical to the first run
- Fixture C (existing content preserved): create `AGENTS.md` with content outside the markers before first run; assert that content survives the injection
- Confirm tests fail before implementation
- Commit with suffix `[red]`: `feat(soa-sync): agent-rule injection [red]`

## Green

- Author `AGENTS.soa.md` at repo root:
  - Section 1 — Skill triggers: list all skills under `.son-of-anton/.agents/skills/` with their trigger commands (use consumer paths)
  - Section 2 — Subagent review rules: same-type default, adversarial prompt required, no rationalizing findings
  - Section 3 — Pre-commit discipline: `bun run format`, `bun run verify`, spellcheck on docs/copy changes
- Author `CLAUDE.soa.md` at repo root with the same three sections rewritten for Claude (imperative, direct language matching existing `CLAUDE.md` style)
- Add to `soa-sync.sh` consumer-mode block:
  - `inject_soa_block <source_file> <target_file>`: reads `<source_file>`, replaces or inserts between `<!-- soa:start -->` and `<!-- soa:end -->` in `<target_file>`; creates `<target_file>` if absent; compares before writing so re-runs are truly no-op
  - Call `inject_soa_block AGENTS.soa.md AGENTS.md` and `inject_soa_block CLAUDE.soa.md CLAUDE.md`
  - Print lint-ignore warning after injection
- Commit with suffix `[green]`: `feat(soa-sync): agent-rule injection [green]`

## Refactor

- If `inject_soa_block` grows beyond ~20 lines, extract marker parsing into a named helper
- Only refactor what you touched

## Review Focus

- `AGENTS.soa.md` and `CLAUDE.soa.md` must contain only consumer-path references (`.son-of-anton/.agents/skills/`) — no source-repo paths, no source-repo commands
- Idempotency: the comparison before write must be byte-exact, not line-count-based
- Existing content outside the markers must be preserved (Fixture C)
- Source-repo guard: confirm `IS_SOURCE_REPO=true` path never calls `inject_soa_block`
- Lint-ignore warning is printed only in consumer mode

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `AGENTS.soa.md` does not exist; no injection logic in `soa-sync.sh`
Why this path: authoring and injection land together so the injection is testable against real content from day one
Alternative considered: separate authorship ticket — rejected because injection is untestable without real source files; placeholder content would require a second content pass
Deferred: `AGENTS.soa.md`/`CLAUDE.soa.md` content divergence (truly distinct content for Claude vs. agent-agnostic tools) — deferred until there is a concrete reason per product plan
Contract note: none
