---
name: soa
description: Son-of-Anton canonical entrypoint. Use for /soa plan, /soa decompose, /soa execute, /soa resume, /soa preflight, /soa triage-ticket, /soa triage-standalone, /soa triage-advisory-observations (/soa tao), /soa install, /soa update, /soa closeout, and /soa ideate. Manages installation, updates, and the full delivery lifecycle.
---

# Son-of-Anton Skill

Manages son-of-anton installation, updates, and the full delivery lifecycle.

Public slash-command entrypoint: `/soa`.

## Commands

Dispatch on the first word of `$ARGUMENTS`.

---

### `install`

**Trigger:** `/soa install`

Add son-of-anton to the current repo for the first time:

```bash
git subtree add --prefix .son-of-anton https://github.com/cesarnml/son-of-anton.git main --squash
bash .son-of-anton/scripts/soa-sync.sh
```

If `.son-of-anton` already exists, tell the user to use `update` instead.

`soa-sync.sh` wires the Claude Code adapter as `/soa` plus `soa-*` helper
skills. The prefixed helper names are intentional so existing user skills named
`grill-me`, `pr-review`, `enter-worktree`, etc. are not shadowed.

---

### `update`

**Trigger:** `/soa update`

Pull the latest changes from son-of-anton in **consumer repos**, then re-sync
skill symlinks.

If `.son-of-anton/scripts/soa-update.sh` exists, run:

```bash
bash .son-of-anton/scripts/soa-update.sh
```

Otherwise run the manual recipe (legacy consumers before this script shipped):

```bash
git fetch https://github.com/cesarnml/son-of-anton.git main
UPSTREAM_SHA="$(git rev-parse FETCH_HEAD)"
git subtree merge --prefix .son-of-anton "$UPSTREAM_SHA" --squash
bash .son-of-anton/scripts/soa-sync.sh
UPSTREAM_HASH="$(git show "$UPSTREAM_SHA":docs/template/delivery/adversarial-review-template.md | git hash-object --stdin)"
LOCAL_HASH="$(git hash-object .son-of-anton/docs/template/delivery/adversarial-review-template.md)"
test "$UPSTREAM_HASH" = "$LOCAL_HASH"
```

Fetch upstream first, capture `UPSTREAM_SHA`, and merge that commit — not plain
`main` (which can resolve through the consumer repo's local branch history) and
not bare `FETCH_HEAD` after later git commands may have moved it.

Path mapping for verification: upstream files live at `docs/...` in the
Son-of-Anton repo; in consumer repos the same content is at
`.son-of-anton/docs/...`.

Those hashes must match. If they do not, report the update as failed and do not
claim the repo is current.

Report what changed. If already up to date, say so.

The sync step is required after every update. It refreshes `/soa` and removes
stale `soa-*` helper symlinks before relinking the current helper set.

---

### `ideate`

**Trigger:** `/soa ideate [topic]`

**Optional.** Use when developer intention is too half-formed to yield a concrete plan directly. Skip this and go straight to `/soa plan` when the idea is already clear or comes from a retrospective follow-up.

Turn a developer ideation storm into a draft phase plan that feeds `/soa plan`.

1. Ask the developer open-ended questions to surface goals, constraints, and unknowns. Be relentless — this is the `soa-grill-me` stage for ideas, not plans.
2. Synthesize the conversation into a concise draft phase summary (title, goal, proposed scope, open questions).
3. **Stop and seek developer approval of the summary before writing any files.**
4. Once approved, write the draft to `docs/product/drafts/<slug>.md`.

> The next step is `/soa plan docs/product/drafts/<slug>.md`.

---

### `plan`

**Trigger:** `/soa plan [path-to-plan or inline description]`

**Output: `docs/product/plans/phase-N.md` only — the "what" and "why". No tickets. No implementation details.**

Accepts a concrete idea (inline description), a draft from `/soa ideate` (`docs/product/drafts/<slug>.md`), or any existing rough plan. Runs an `soa-grill-me` session scoped to product-level decisions: goals, success criteria, scope, explicit deferrals, and dependencies. The session ends when `docs/product/plans/phase-N.md` is written and approved.

1. Read the plan if a file path is given. Otherwise use the inline description.
2. **Invoke the `soa-grill-me` skill** in **Mode 1 (product plan)** — pass the plan content and instruct it to stay at the product level (scope, goals, success criteria, deferrals, risks). Explicitly tell it: no schema design, no API routes, no ticket breakdown.
3. After `soa-grill-me` closes, write `docs/product/plans/phase-N.md` using the product-plan template at `.son-of-anton/docs/template/stubs/product-plan.template.md`.
4. **Hard stop.** Ask the developer to approve the product plan. Do not proceed to tickets.

> The next step after approval is `/soa decompose docs/product/plans/phase-N.md`.

---

### `decompose` (alias: `decomp`, `tickets`)

**Trigger:** `/soa decompose [path]` or `/soa decomp` or `/soa tickets`

**Output: `docs/product/delivery/phase-N/implementation-plan.md` + ticket files — the "how". Requires an approved product plan as input.**

Take the approved `docs/product/plans/phase-N.md` and produce a detailed delivery plan with exact ticket decomposition.

1. Read the product plan at the given path (or ask for it). Refuse to proceed if no approved product plan exists — send the developer to `/soa plan` first.
2. **Invoke the `soa-grill-me` skill** in **Mode 2 (delivery decomposition)** — pass the product plan and focus on: schema/migration strategy, API route structure, ticket granularity, PR slice boundaries, dependency order, test strategy, exit conditions per ticket.
3. **Stop and seek developer approval of the ticket list** before writing files.
4. Before writing any ticket file, read the canonical template at `docs/template/stubs/ticket.template.md`. Do not use existing ticket files as format references — they may predate the current template and will produce format drift if copied. Then write `docs/product/delivery/phase-N/implementation-plan.md` and individual `ticket-NN-*.md` files per that template.
5. After files are written and developer approves, surface this prompt:

   > Files written. Run `/soa preflight phase-N` to verify template compliance before starting execution.

---

### `preflight`

**Trigger:** `/soa preflight <phase-N>`

Template-compliance gate between decompose and execute. Reads `implementation-plan.md` and all ticket files for the named phase and checks them against the canonical stubs in `docs/template/stubs/`. Reports a structured PASS/FAIL checklist. Must PASS before `/soa execute` is invoked.

**Invoke the `soa-preflight` skill** — pass the phase name and the path to the delivery directory.

Do not proceed to `/soa execute` if preflight reports any failures. List all issues and ask the developer to fix them first.

---

### `execute`

**Trigger:** `/soa execute <phase-XX|epic-XX>`

Begin orchestrated delivery of the named phase or epic.

Read these files before doing anything else — they are gospel:

- `.son-of-anton/docs/template/overview/start-here.md`
- `.son-of-anton/docs/template/delivery/delivery-orchestrator.md` (read in full)
- `.son-of-anton/docs/template/delivery/son-of-anton.md`
- `.son-of-anton/orchestrator.config.json`

Then:

1. Locate the `implementation-plan.md` for the named phase/epic.
2. Identify the first unstarted ticket.
3. Execute via the orchestrator path — **do not ad-hoc implement**.
4. Valid stopping points are defined in `delivery-orchestrator.md` and `orchestrator.config.json`. Respect them.
5. At each stopping point, surface the canonical resume prompt so the developer can continue with `/soa resume`.

---

### `resume`

**Trigger:** `/soa resume <phase-XX|epic-XX>`

Resume delivery after a stopping point.

1. Read `.son-of-anton/docs/template/delivery/delivery-orchestrator.md` in full and `orchestrator.config.json`.
2. Check `state.json` for the last recorded position, or run `git worktree list` to identify active worktrees.
3. Read the handoff notes from the last stopping point.
4. Continue from exactly where delivery left off — do not restart, do not re-plan.
5. Stick to the orchestrator path as configured.

---

### `triage-ticket`

**Trigger:** `/soa triage-ticket PR#<number>`

Reconcile late external AI review comments on a **done ticket-linked phase PR**.
This command is only for PRs that belong to an already-delivered ticket in a
phase/epic stack. For standalone PRs, use `/soa triage-standalone PR#<number>`.

1. Parse the PR number from `PR#<number>`, `#<number>`, or `<number>`. Ask for a
   PR number if it is missing or ambiguous.
2. Read `.son-of-anton/docs/template/delivery/delivery-orchestrator.md` in full
   when running in a consumer repo; in the Son-of-Anton source repo, read
   `docs/template/delivery/delivery-orchestrator.md`.
3. Locate delivery state by searching `.agents/delivery/*/state.json` in the
   current checkout and known `git worktree list` entries for tickets whose
   `prNumber` matches the PR number.
4. Refuse to continue unless the matches resolve to exactly one ticket identity
   (`planPath` + ticket id) and that ticket's status is `done`. Ignore duplicate
   mirrored state files only when they agree on that identity and status. If the
   PR is standalone, unknown to delivery state, matched by conflicting states,
   or attached to a non-`done` ticket, stop and explain the correct command or
   missing state.
5. Run from the matched ticket's recorded `worktreePath` when available; if the
   orchestrator emits a worktree-guard recovery command, follow it exactly:

```bash
bun run deliver --plan <state.planPath> triage-ticket <ticket-id>
```

6. Apply the `soa-pr-review` stance to any findings: patch only prudent
   actionable issues, push fixes, resolve native inline threads that are
   patched/already-outdated/rejected when resolvable, and let the orchestrator
   refresh the PR body best-effort.

---

### `triage-standalone`

**Trigger:** `/soa triage-standalone PR#<number>`

Run the standalone PR external AI review triage path for a non-ticketed PR.
This command is only for standalone PRs. For done ticket-linked phase PRs, use
`/soa triage-ticket PR#<number>` so delivery state and review artifacts remain
authoritative.

1. Parse the PR number from `PR#<number>`, `#<number>`, or `<number>`. Ask for a
   PR number if it is missing or ambiguous.
2. Read `.son-of-anton/docs/template/delivery/delivery-orchestrator.md` in full
   when running in a consumer repo; in the Son-of-Anton source repo, read
   `docs/template/delivery/delivery-orchestrator.md`.
3. If `.agents/delivery/*/state.json` contains a ticket with this `prNumber`,
   stop and direct the operator to `/soa triage-ticket PR#<number>` instead.
4. Surface that standalone triage uses real wall-clock polling, then run:

```bash
bun run deliver triage-standalone --pr <number>
```

5. Apply the `soa-pr-review` stance to any findings: patch only prudent
   actionable issues, push fixes, resolve native inline threads that are
   patched/already-outdated/rejected when resolvable, and let the standalone
   review flow refresh the PR body best-effort.

---

### `triage-advisory-observations` (alias: `tao`)

**Trigger:** `/soa triage-advisory-observations <phase-XX|epic-XX>` or `/soa tao <phase-XX|epic-XX>`

Run the post-phase advisory-observation triage lane after the stacked phase has
landed on the configured `closeoutBranch` and before the next phase starts. This
is for non-blocking `Advisory Observations` from subagent-review reports. It is
not a per-ticket pre-PR gate and it must not apply patches automatically.

1. Parse the phase or epic target and locate its `implementation-plan.md`.
2. Read `docs/template/delivery/delivery-orchestrator.md` in the source repo
   (or `.son-of-anton/docs/template/delivery/delivery-orchestrator.md` in a
   consumer repo) before running commands.
3. Resolve or create an explicit dispositions input file for every parsed
   advisory observation. Do not guess dispositions from report prose.
4. Run the underlying command from the checkout where the phase delivery state
   is authoritative:

```bash
bun run deliver --plan <plan-path> triage-advisory-observations --dispositions <path>
```

5. Report the written triage artifact path and any warnings about untriaged
   observations or suspicious report evidence. Keep `Actionable findings`
   separate: they remain the blocking reconciliation lane and are not part of
   advisory-observation disposition.

---

### `closeout` (alias: `closeout-stack`)

**Trigger:** `/soa closeout XX`

Squash-merge a completed stacked PR set onto main.

Run the closeout script:

```bash
bun run .son-of-anton/scripts/closeout-stack.ts
```

Pass any argument (stack name or number) through to the script. Report the result. If the script is not found, tell the user to complete the setup steps in the README.
