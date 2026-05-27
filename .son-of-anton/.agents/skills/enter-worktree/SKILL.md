---
name: soa-enter-worktree
description: Bootstrap a fresh worktree before starting work. Trigger when node_modules may be missing or a newly created worktree needs setup.
---

# Enter Worktree

## Trigger policy

This skill is **runtime-agnostic**. Do not gate it on Bun-only repos or Bun-only worktrees.

Use it whenever a worktree is fresh enough that gitignored local bootstrap files may be missing, especially:

- `node_modules` is absent
- the worktree was newly created
- `.env` or other gitignored local config is likely missing

Reason: a fresh checkout can fail verification even when the primary checkout is healthy, because SvelteKit/Vite-generated env typings depend on local `.env` files being present in the current worktree.

## Steps

1. **Install dependencies** — if `node_modules` is absent, install them. Use whatever package manager this repo uses.

2. **Copy gitignored files from primary worktree** — these are not present in a fresh checkout:
   - `.env` — credentials and runtime config
   - `.gitignore` — keeps artifacts (`handoffs/`, `reviews/`, `state.json`) out of commits

## Guardrails

- Skip any step that's already done.
- Don't reinstall deps unless they're missing or clearly broken.
- Prefer copying the primary worktree's gitignored bootstrap files before running repo verification commands.
