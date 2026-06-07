# Contributing to Son of Anton

Thanks for your interest. Son of Anton is a delivery orchestrator — the codebase is the same tool it uses to ship itself, so the best way to understand a contribution is to run the workflow end to end at least once before changing it.

**New here?** Read [How Son of Anton Works — A Newcomer's Mental Model](docs/how-son-of-anton-works.md) first. It builds the mental model (no prior knowledge assumed) and maps every concept to where it lives in the code, so the rest of this guide makes sense.

## Prerequisites

- [Bun](https://bun.sh) ≥ 1.0
- [Claude Code](https://claude.ai/code) (or another agent that reads `AGENTS.md`)
- A GitHub account with `gh` CLI configured

## Setup

```bash
git clone https://github.com/cesarnml/son-of-anton.git
cd son-of-anton
bun install
bun run ci          # format check + lint + tests — should all pass on a clean clone
```

## Repo layout

```
tools/delivery/     core orchestrator logic (TypeScript)
scripts/            bun entry points (deliver.ts, closeout-stack.ts, etc.)
tests/              bun:test test suite
docs/template/      delivery workflow docs the orchestrator reads at runtime
  delivery/         orchestrator internals: TDD workflow, PR templates, review templates
  overview/         start-here.md — read this before working on orchestrator behavior
.agents/            agent-facing skills and delivery state
  skills/           Claude Code skills used in orchestrated delivery
notes/              design stance docs and proposals (public/ is checked in)
```

## Dev commands

| Command          | What it does                                        |
| ---------------- | --------------------------------------------------- |
| `bun run format` | Biome + Prettier — **run this before every commit** |
| `bun run verify` | Format check + lint (no writes)                     |
| `bun run ci`     | Full check: verify + tests                          |
| `bun test`       | Tests only                                          |

**Format before you stage.** The CI enforces it. If you commit without formatting first, the next CI run rewrites the file and leaves a dirty tree.

## Making a change

1. **Read `docs/template/overview/start-here.md`** before touching orchestrator behavior. It describes the four gates and how delivery state flows.
2. Fork the repo and create a branch from `main`.
3. Make your change. For anything touching orchestrator logic, add or update a test in `tests/`.
4. Run `bun run format`, then `bun run ci`. Fix anything that fails.
5. Open a PR.

## Commit style

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): description`.

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`.

```
feat(tdd): add refactor-review subagent gate
fix(reconciliation): handle missing ledger rows on skipped tickets
docs(template): clarify post-red trigger conditions
```

Keep the subject line under 72 characters. No period at the end.

## Pull requests

- One logical change per PR.
- The PR title should follow the same Conventional Commit format as your commits.
- If your change affects the delivery workflow, update the relevant doc in `docs/template/delivery/`.
- If your change affects user-visible commands or behavior, update `README.md` and `docs/template/overview/start-here.md`.

There is no formal review SLA. Smaller, focused PRs move faster.

## What "advisory" means in this repo

Several tools in the orchestrator run as "advisory" subagents — they report findings but do not commit or modify files. If you are building on the orchestrator, keep that invariant: subagent runners are stdout-only. The primary agent adjudicates and decides what to apply.

## Getting oriented

- **New to the workflow?** Start with the README, then `docs/template/overview/start-here.md`.
- **Working on orchestrator internals?** Read `docs/template/delivery/delivery-orchestrator.md` before touching `tools/delivery/`.
- **Proposing a design change?** Open an issue first. Design decisions for the orchestrator are load-bearing — a brief discussion before a PR saves everyone time.
- **Questions?** Open an issue with the `question` label.
