# P6.04 README and Docs

Size: 1 point
Type: docs
Scope: docs

## Outcome

- `README.md` explains: why `.son-of-anton/` is not gitignored (subtree commits content into history; gitignoring breaks `git subtree pull`), injection behavior and `<!-- soa:start -->` / `<!-- soa:end -->` marker convention, `.soa-sync-version` and migration runner contract, manual lint-ignore step with examples for prettier, eslint, and biome
- `docs/template/overview/start-here.md` updated if any scope or commands changed in this phase

## Red

- Docs-only; no failing test
- Manual check before starting: confirm P6.01, P6.02, P6.03 PRs are open and reviewed
- Verify `README.md` currently lacks the four sections listed above — this is the "failing state"
- Commit with suffix `[red]`: `docs(docs): readme and start-here updates [red]`

## Green

- Add or update `README.md` with the following sections (under existing structure, do not restructure the whole file):
  - **Why `.son-of-anton/` is not gitignored** — subtree vs. submodule explanation; gitignore breaks `git subtree pull`
  - **Injection behavior** — what `bun run sync` does to consumer `AGENTS.md` and `CLAUDE.md`; marker convention; idempotency guarantee
  - **Migration runner contract** — `.soa-sync-version`, `SOA_TARGET_VERSION`, when to bump and add a migration function
  - **Manual lint-ignore step** — exact entries for prettier (`.prettierignore`), eslint (`.eslintignore` or `eslint.config.*`), biome (`biome.json`)
- Review `docs/template/overview/start-here.md` — update any commands or scope descriptions that changed in P6.01–P6.03
- Commit with suffix `[green]`: `docs(docs): readme and start-here updates [green]`

## Refactor

- None

## Review Focus

- README sections are accurate for the behavior shipped in P6.01 and P6.03 — not aspirational
- Lint-ignore examples cover at least prettier, eslint, and biome; entries are copy-pasteable
- `start-here.md` command names match the actual `package.json` scripts (e.g. `bun run sync` not `bun run sync-skills`)

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: README lacks subtree explanation, injection docs, migration contract, and lint-ignore guidance
Why this path: docs ticket is last in the stack so it can accurately reflect shipped behavior rather than specifying it
Alternative considered: writing docs in P6.01 alongside the runner — rejected because injection behavior (P6.03) is not yet defined at P6.01 time; docs would need a second pass
Deferred: none
Contract note: none
