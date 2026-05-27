# Phase 6: soa-sync Refactor — Consumer Upgrade Story

**Delivery status:** Product plan approved. Ready for decomposition.

## TL;DR

**Goal:** Make `soa update` a complete upgrade — consuming repos get current skills, current structural layout, and current agent guidance injected automatically, without manual follow-up steps.

**Ships:**

- `scripts/soa-sync.sh` (renamed from `sync-skills.sh`) with migration runner and version marker
- `AGENTS.soa.md` and `CLAUDE.soa.md` — consumer-facing tooling rule templates (skill triggers, subagent review rules, pre-commit discipline; consumer-path-correct)
- Idempotent injection of `AGENTS.soa.md` → consumer `AGENTS.md` and `CLAUDE.soa.md` → consumer `CLAUDE.md` via `<!-- soa:start -->` / `<!-- soa:end -->` markers
- `run_migration_1()`: moves `.agents/delivery/*/reviews/` → `docs/product/delivery/*/reviews/` in this repo; orchestrator, closeout-stack, son-of-anton-ethos, and delivery-orchestrator.md updated to the new path
- `docs/product/retrospectives/` as the canonical retrospective home; existing `notes/public/` retros migrated; `soa-write-retrospective` skill updated
- Lint/format ignore patching removed; replaced with a clear warning printed by soa-sync pointing devs to add `.son-of-anton/` manually
- README and start-here updated with subtree-vs-submodule explanation, injection behavior, migration runner contract, and manual lint-ignore steps

**Defers:**

- Auto-patching config-based linters (`biome.json`, `eslint.config.*`, etc.) — too varied; manual step documented in README is the gate
- Consumer-side reviews migration — consumers have no reviews to migrate; migration runner is a no-op for them at `SOA_TARGET_VERSION=1`
- Multi-consumer testing — only one consumer exists today; end-to-end upgrade verification is manual

---

After every `soa update`, consuming repos have current skills but stale or absent agent guidance — Claude ignores SoA rules because the files it actually reads (`CLAUDE.md`, `AGENTS.md`) are never updated. This phase closes that gap by making `soa-sync.sh` responsible for the full upgrade: structural migrations, agent-rule injection, and a version marker that makes re-runs safe and future migrations incremental.

## Phase Goal

This phase should leave the product in a state where:

- Running `soa update` followed by `bun run sync` in a consumer repo produces a fully current repo: skills symlinked, `AGENTS.md` and `CLAUDE.md` updated with SoA tooling rules, `.soa-sync-version` written, lint-ignore warning printed
- Re-running `bun run sync` when already current is a no-op — no mutations, no duplicate marker blocks
- All delivery review artifacts in this repo live under `docs/product/delivery/*/reviews/`; nothing references the old `.agents/delivery/*/reviews/` path
- All retrospectives live under `docs/product/retrospectives/`; `notes/public/` is empty of retros
- `CLAUDE.soa.md` and `AGENTS.soa.md` exist and contain only consumer-appropriate tooling rules (no source-repo commands, no source-repo paths)

## Committed Scope

### Migration runner (foundational)

- `SOA_TARGET_VERSION` constant in `soa-sync.sh`; `apply_migrations()` runs numbered functions from `(current + 1)` to target, updates `.soa-sync-version`
- Source repo skips migration logic entirely (`IS_SOURCE_REPO` branch)
- Idempotent: already-at-target version is a no-op
- Delivery ticket template updated with "bump `SOA_TARGET_VERSION` and add migration function when moving tracked files" checklist item

### Script rename

- `scripts/sync-skills.sh` → `scripts/soa-sync.sh`; `package.json` `sync` script updated; no functional change

### Reviews path migration (this repo only)

- `run_migration_1()`: moves `.agents/delivery/*/reviews/` → `docs/product/delivery/*/reviews/` for all existing phases
- Orchestrator script, `closeout-stack` skill, `son-of-anton-ethos` skill, and `delivery-orchestrator.md` updated to reference the new path
- Old closed-phase `state.json` files left as-is (frozen artifacts; nothing reads them post-closeout)

### Retrospective location migration (this repo only)

- `docs/product/retrospectives/` created; existing `notes/public/` retros moved there with plan-slug naming
- `soa-write-retrospective` skill path reference updated

### Agent-rule injection (consumer mode only)

- `AGENTS.soa.md` authored: skill triggers (`.son-of-anton/.agents/skills/` paths), subagent review rules, pre-commit discipline
- `CLAUDE.soa.md` authored: same three sections, Claude-optimized language
- `soa-sync.sh` injects each into consumer `AGENTS.md` / `CLAUDE.md` via `<!-- soa:start -->` / `<!-- soa:end -->` markers; creates file if absent (flat file, not symlink); idempotent upsert on re-run
- Source repo's `AGENTS.md` and `CLAUDE.md` are never touched by injection logic

### Lint/format ignore (consumer mode only)

- Auto-patching of `.prettierignore` / `.eslintignore` removed from scope
- `soa-sync.sh` prints a single warning line: add `.son-of-anton/` to your lint/format ignore configuration
- README documents exact entries for common tools (prettier, eslint, biome)

### README and docs

- Explain why `.son-of-anton/` is not gitignored (subtree commits content into history; gitignoring breaks `git subtree pull`)
- Document injection behavior, marker convention, `.soa-sync-version` and migration runner contract
- Document manual lint-ignore step with examples for prettier, eslint, biome
- Update `docs/template/overview/start-here.md` if scope or commands changed

## Explicit Deferrals

- **Config-based linter auto-patching** — `biome.json`, `eslint.config.*` structures are too varied to parse reliably; manual step with README guidance is sufficient
- **Consumer-side reviews migration** — consumers own no review artifacts; `run_migration_1()` is a no-op for them by design
- **`CLAUDE.soa.md` / `AGENTS.soa.md` divergence** — today the two files are near-identical; splitting into truly distinct content for Claude vs. agent-agnostic tools is deferred until there is a concrete reason
- **Interactive soa-sync approval prompts** — intentionally not added; git diff is the review mechanism

## Exit Condition

A developer who clones a fresh consumer repo, runs `git subtree add` to install SoA, then runs `bun run sync` sees: skills symlinked, `AGENTS.md` and `CLAUDE.md` updated with SoA tooling rules, `.soa-sync-version` set to `1`, and a lint-ignore warning printed. Running `bun run sync` again produces no mutations. In this repo, every `reviews/` directory is under `docs/product/delivery/`, every retrospective is under `docs/product/retrospectives/`, and no skill or script references the old paths.

## Retrospective

`required` — this phase establishes the migration runner contract and the `*.soa.md` injection pattern that all future phases build on; non-obvious decisions (warn-not-patch for linters, `AGENTS.soa.md`/`CLAUDE.soa.md` split, frozen state.json policy) are worth capturing before they get relitigated.
