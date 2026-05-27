---
name: soa-closeout-stack
description: Merge a completed stacked PR phase onto main. Use when the developer approves closeout after a multi-ticket delivery is fully reviewed.
---

# Closeout Stack

Merge a completed stacked delivery phase onto `main` after the developer approves all PRs.

## Primary Path

```bash
git checkout main
bun run closeout-stack --plan <plan-path>
```

Processes each ticket in stack order via `git merge --squash` (3-way, robust against parent patches). For each ticket: fetch + reset local `main` to `origin/main`, squash-merge the ticket branch, commit with PR title, push to `origin/main`, close PR, delete remote branch. Produces one squash commit per ticket on `main` when squash succeeds.

If `merge --squash` hits conflicts (common after earlier tickets were squash-merged so SHAs diverge from the stacked branches), `closeout-stack` resets to `origin/main`, reads the PR’s commits via `gh pr view --json commits`, and lands them in order with `git cherry-pick` (merge commits use `-m 1`). When a picked commit is already fully present on `main` (empty patch), it runs `git cherry-pick --skip` and continues. That may yield multiple commits on `main` for one ticket. If cherry-pick fails for any other reason, recover manually using the checklist below.

### Delivery artifact mirror (`state.json`, `reviews/`, `handoffs/`)

Closeout reads `.agents/delivery/<plan-key>/state.json` from the repo you run the command in. The orchestrator only writes delivery artifacts in the **current working directory** where you ran `deliver` — so across a stacked phase, `reviews/` and `handoffs/` files often land in **different ticket worktrees**, not only the last one.

Before `closeout-stack` (or any command you run from the primary checkout), mirror delivery artifacts into that checkout:

- **`state.json`:** copy from the **ticket worktree where the final ticket was advanced to `done`** (or whichever worktree last wrote state). That file is the single control-plane index; earlier worktrees hold stale partial state.
- **`reviews/` and `handoffs/`:** copy **from every ticket worktree** used during the phase into the primary tree — `reviews/` to `docs/product/delivery/<plan-key>/reviews/` and `handoffs/` to `.agents/delivery/<plan-key>/handoffs/`, **merging** per-ticket filenames (they normally do not collide). Goal: **all** review fetch/triage artifacts and **all** handoff markdown files exist on `main`, not only the set generated in the final worktree.

If you skip this, `closeout-stack` may see wrong PR numbers, and the primary checkout loses local review and handoff evidence that never left an older worktree. See `docs/template/delivery/delivery-orchestrator.md` (State file and primary checkout).

Example (adjust paths and plan key):

```bash
mkdir -p docs/product/delivery/<plan-key>/reviews .agents/delivery/<plan-key>/handoffs

# Authoritative stack index — from the worktree that completed the last ticket
cp /path/to/final-ticket-worktree/.agents/delivery/<plan-key>/state.json \
   .agents/delivery/<plan-key>/state.json

# Merge every ticket worktree’s reviews and handoffs back to primary
for wt in /path/to/phase-wt-01 /path/to/phase-wt-02 /path/to/phase-wt-NN; do
  cp -R "$wt/docs/product/delivery/<plan-key>/reviews/"* docs/product/delivery/<plan-key>/reviews/ 2>/dev/null || true
  cp -R "$wt/.agents/delivery/<plan-key>/handoffs/"* .agents/delivery/<plan-key>/handoffs/ 2>/dev/null || true
done
```

After success, clean up:

```bash
git worktree list
git worktree remove <path>   # for each phase worktree
git remote prune origin
```

## Recovery

If closeout fails mid-flight (including after an automatic cherry-pick attempt), do not blindly re-run the script. Instead:

1. Check `git log --oneline origin/main` and GitHub PR state to see what merged.
2. `git checkout main && git reset --hard origin/main`
3. For each remaining ticket:
   ```bash
   git fetch origin <ticket-branch>
   git merge --squash origin/<ticket-branch>
   git commit -m "<PR title>"
   git push origin main
   gh pr close <number> --comment "Squash-merged manually" --delete-branch
   ```
4. Confirm `origin/main` has expected squash commits in ticket order.
5. Sync delivery artifacts to the primary `main` checkout: copy **`state.json`** from the worktree that last advanced the stack; **merge** all **`reviews/`** and **`handoffs/`** files from **every** ticket worktree used in the phase so nothing stays stranded off `main`.
6. Write `docs/product/retrospectives/<plan>-retrospective.md` if not already done.

## Key Rules

- Developer must explicitly approve closeout. Never run autonomously.
- `merge --squash` conflicts are handled automatically via sequential `git cherry-pick` of the PR’s commits; only unresolved cherry-pick conflicts need manual resolution.
- Verify the test suite passes on `main` after closeout.
