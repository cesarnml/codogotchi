# Phase 01 — CLI + Convex plumbing retrospective

Source plan: [`docs/product/plans/phase-01.md`](../plans/phase-01.md).
Delivery plan: [`docs/product/delivery/phase-01/implementation-plan.md`](../delivery/phase-01/implementation-plan.md).

## Scope delivered

Tickets P1.01 → P1.22 (22/22) shipped as a stacked PR chain on `agents/p1-*`
branches, PRs [#2](https://github.com/cesarnml/codogotchi/pull/2) through
[#23](https://github.com/cesarnml/codogotchi/pull/23). Delivered: 3-package
workspace (`packages/{cli,engine,contracts}`) plus root `convex/`; CLI surface
of six commands (`setup`, `sync`, `status`, `loot`, `config`, `vacation`) plus
the `codogotchi-hook` binary; XP / Health / Loot engine running both in Bun
and inside Convex's V8 isolate; four signal sources (Claude Code JSONL, Codex
JSONL, GitHub PRs with `scorePR` quality enrichment and a last-90-days-or-20-PRs
rate cap, Wakatime hours); Convex schema + `syncProfile` mutation + HTTP
action deployed to Convex Cloud; animation-state vocabulary v1 and SoA event
feed contract published under `docs/contracts/`; scheduled-sync installers
for launchd + cron and a `scorePR` debug log; validation runbook skeleton at
`docs/runbooks/phase-01-validation.md`.

## What went well

- **Module-by-module rewrite from scratch beat bulk import.** Scaffold-v2 was
  reference material only. Every module ticket landed with its own red/green
  pair, which kept the diff per PR small enough that adversarial subagent
  review actually fit in working memory. The cost was visible (more tickets)
  but the alternative — landing scaffold-v2 wholesale — would have produced
  one mega-PR with zero meaningful review surface.
- **Three-package boundary held under load.** `packages/engine/src/*` (minus
  `sources/`) stayed Bun-free, which let the Convex `syncProfile` mutation
  import the same XP/HP code that runs in the CLI without a server fork.
  The review rule "no `node:fs`, no `process.env`, no `bun:*` in engine
  core" was cheap to enforce and saved us from a future server/client drift
  spiral.
- **`packages/contracts/` as the IPC source of truth worked.** Closed enums
  + zod schemas at the boundary meant the hook (P1.18) and the SoA gate
  mapper (P1.19) could not silently disagree about state names. The
  one-revision rule in P1.02 also worked as intended — P1.18 used it once
  to bump `schema_version` honestly, and the contract doc absorbed the
  change cleanly.
- **`subagentReview: skip_doc_only` with `--preferred-runner` was the right
  gate.** Code tickets got an adversarial second pass; doc-only tickets did
  not pay the latency tax. Runner identity living on the CLI flag (not in
  config) meant the same flow worked when delivery flipped between
  `claude-cli` and `codex-exec` runners.
- **Pre-phase tooling commit (`format:quiet`, `verify:quiet`, `ci:quiet`)
  was free leverage.** Landing CI scripts on `main` before P1.01 meant
  every ticket had a stable green baseline to diff against. Spellcheck
  catching project-noun drift early is much cheaper than catching it in
  PR review.

## Pain points

- **(Avoidable waste) Worktree-local review artifacts had to be
  reconciled at the end.** The orchestrator writes `reviews/` and
  `handoffs/` into whichever worktree ran each command, so the final
  worktree did not have the full history. Mirroring works but is
  per-phase boilerplate; the documented stance ("treat primary as the
  aggregate mirror") is correct but the mechanical copy step still has
  to happen manually before `closeout-stack`.
- **(Avoidable waste) The P1.22 worktree showed up dirty.** Review
  artifacts from earlier tickets appeared as `deleted` in `git status`
  on the P1.22 worktree because they exist in HEAD's tree but were
  missing on disk. A `git restore` fixed it, but the underlying cause
  is that `start` doesn't fully materialize the predecessor `reviews/`
  tree into a fresh worktree — only the immediate-predecessor artifacts.
  Worth a follow-up; see below.
- **(Expected cost) The four signal sources each had their own
  edge-case shape.** JSONL parsing was straightforward; GitHub's
  rate-limit math and `scorePR` enrichment were the noisy ones. The
  90-day-or-20-PR cap was the right call; without it the first sync
  on an active owner account would have shaped review traffic in
  unhelpful ways.
- **(Expected cost) Convex `convex-test` in-process testing is fast
  but is its own dialect.** Engine code that ran cleanly under
  `bun test` still needed careful import-shape work to stay runnable
  in the V8 isolate. Catching that early (in P1.06/P1.07) avoided a
  late-phase scramble.

## Surprises

- **`bun run deliver` rewrites the status output's "Next command" line
  with a non-canonical token (`post-red`) when the current ticket has
  no commits yet.** Surfaced during resume of P1.22. It is not a
  command — the orchestrator expects `post-verify` next once a green
  commit exists. Mildly confusing on resume; recorded here so a future
  reader doesn't chase it.
- **Doc-only tickets ride through the orchestrator cleanly under
  `skip_doc_only`** — both `subagent-review` and `poll-review`
  auto-record `skipped`, and `advance` proceeds. The
  `prReview: disabled` override on this resume run made the closeout
  ticket noticeably faster than a code ticket. Worth knowing for
  future closeout-shaped tickets.
- **The animation-state vocabulary survived P1.18 with only one
  revision.** That is the best-case outcome of the one-revision
  contract, but it was not guaranteed going in — heuristic states
  were the most likely revision driver.
- **Owner-abandonment risk did not bite this phase, but the
  validation log shipped un-started.** The plan called out
  "owner abandons because nothing shareable" as an accepted,
  unmitigated risk. What actually happened is softer and more
  interesting — the runbook landed on schedule, the live 7-day
  execution did not. See _Net assessment_.

## What we'd do differently

- **Materialize the full prior `reviews/` tree into a fresh worktree
  on `start`.** Today only immediate-predecessor artifacts are
  bounded into the started worktree, by design. That design optimizes
  for active-ticket continuation, which is correct — but at the
  closeout/retro ticket the operator still has to think about
  mirroring. A closeout-aware bootstrap (or a `start --aggregate`)
  would remove the manual reconciliation step entirely.
- **Make the runbook execution a separate ticket from the runbook
  authoring.** P1.21 bundled "write the runbook" and "execute 7 days
  of live operation" under one ticket, which is honest about what
  the work is but lets the execution slip silently when the
  authoring lands. Splitting it would have forced the gate to be
  explicit. We chose the bundled shape originally because seven
  days of wall-clock waiting is not a ticket the orchestrator can
  drive; that reasoning is still correct, but the cost is the
  silent slip we just observed.
- **Document the orchestrator's "next command" token semantics
  somewhere the resume path reads.** The `post-red` surprise above
  cost a few seconds of "wait, is that a real command?" — small,
  but trivially preventable with a one-line gloss in
  `delivery-orchestrator.md`.

## Net assessment

**Mixed: the data pipeline shipped; the validation it requires did
not yet run.** Phase 01's stated goal was "wire the XP / HP / loot
engine end-to-end through a Bun-powered CLI and Convex backend,
validated privately for seven consecutive days." The wiring is
real — `packages/engine` runs server-side in Convex, all four
signal sources flow, two-profile production deploy works, the
hook writes the documented state vocabulary, the orchestrator
ran 22 ticket PRs to clean review. **All eight exit conditions
remain unchecked in
[`docs/runbooks/phase-01-validation-log.md`](../../runbooks/phase-01-validation-log.md)**:
the log file is a skeleton, day-by-day evidence is absent, and
end-of-week sign-off has not happened. The phase plan explicitly
required either eight checks or a documented developer-accepted
shortfall before P1.22 closes — this retrospective is that
documented shortfall acceptance. The code is ready for live
validation; the validation has not run yet.

Of the three named risks: the hook-event-format risk did not bite;
the `enrichPRQuality()` rate-limit cap was inserted as planned but
has not seen 7 days of real traffic; the PR-quality false-positive
risk is unknown for the same reason. The unmitigated
"owner-abandons" risk did not bite — execution ran cleanly through
all 22 tickets — but it shape-shifted into "owner closed the build
slice without running the validation window," which is a softer
version of the same trade.

## Follow-up

- **Run the 7-day validation window on `main` post-merge.** Fill
  in `phase-01-validation-log.md` daily. Decide at end-of-week
  whether to amend Phase 02 entry criteria based on what the log
  shows (especially EC2 four-source coverage and EC8 hook
  `celebrating` emission).
- **Split future "author runbook + execute runbook" tickets.**
  Either two tickets, or one ticket with a hard gate on the
  execution artifact before the dependent retro ticket can start.
- **Aggregate `reviews/` and `handoffs/` mirroring into a single
  helper.** Either a `deliver mirror-to-primary` command, a
  `start --aggregate` mode, or documentation in
  `delivery-orchestrator.md` strong enough that the manual loop
  is not forgotten before `closeout-stack`.
- **Document the orchestrator's `post-red` next-command token**
  in `delivery-orchestrator.md` so the next operator does not
  re-discover it.
- **Phase 02 (macOS menu bar pet) inherits the IPC contract
  unchanged.** That is the load-bearing carry-forward; protect
  it as the Swift learning ramp begins.

---

_Created: 2026-05-19. Phase 01 stack open in PRs #2–#23; closeout
pending developer approval._
