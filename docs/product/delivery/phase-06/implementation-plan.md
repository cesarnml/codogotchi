# Phase 06 — soa-sync Refactor: Consumer Upgrade Story

Status: Delivered — all tickets merged.

> Make `soa update` a complete upgrade — consuming repos get current skills, current structural layout, and current agent guidance injected automatically, without manual follow-up steps.

## Product contract

After this phase ships:

- Running `soa update` followed by `bun run sync` in a consumer repo produces a fully current repo: skills symlinked, `AGENTS.md` and `CLAUDE.md` updated with SoA tooling rules, `.soa-sync-version` written, lint-ignore warning printed
- Re-running `bun run sync` when already current is a no-op — no mutations, no duplicate marker blocks
- All delivery review artifacts in this repo live under `docs/product/delivery/*/reviews/`; nothing references the old `.agents/delivery/*/reviews/` path
- All retrospectives live under `docs/product/retrospectives/`; `notes/public/` is empty of retros
- `CLAUDE.soa.md` and `AGENTS.soa.md` exist and contain only consumer-appropriate tooling rules

## Grill-Me decisions locked

- Test strategy: Bun integration tests shelling out to `soa-sync.sh` in `git init` temp fixtures — fits existing runner, catches regressions automatically
- P6.01 bundles rename + migration runner + `run_migration_1()` + all reference updates + ticket template checklist — atomic delivery of the migration contract
- Delivery ticket template checklist update lands in P6.01 (with the runner, not the docs ticket) — contract documented at the same time it is established
- Lint-ignore warning lands in P6.03 (with injection) — one consumer-mode `soa-sync.sh` pass, tested by the same fixture
- Retrospective migration is its own ticket (P6.02) — distinct files, distinct skill update, clean PR slice
- `AGENTS.soa.md` + `CLAUDE.soa.md` authorship and injection land in one ticket (P6.03) — injection untestable without real source files
- Retrospective: `required` — migration runner contract and `*.soa.md` injection pattern are non-obvious decisions worth capturing before they get relitigated

## Ticket Order

1. `P6.01 Script rename, migration runner, and reviews path migration`
2. `P6.02 Retrospective location migration`
3. `P6.03 Agent-rule injection`
4. `P6.04 README and docs`
5. `P6.05 Phase exit and retrospective`

## Ticket Files

- `ticket-01-script-rename-migration-runner.md`
- `ticket-02-retrospective-location-migration.md`
- `ticket-03-agent-rule-injection.md`
- `ticket-04-readme-and-docs.md`
- `ticket-05-phase-exit-and-retrospective.md`

## Exit Condition

A developer who clones a fresh consumer repo, runs `git subtree add` to install SoA, then runs `bun run sync` sees: skills symlinked, `AGENTS.md` and `CLAUDE.md` updated with SoA tooling rules, `.soa-sync-version` set to `1`, and a lint-ignore warning printed. Running `bun run sync` again produces no mutations. In this repo, every `reviews/` directory is under `docs/product/delivery/`, every retrospective is under `docs/product/retrospectives/`, and no skill or script references the old paths.
