# Phase 17 Retrospective — Codogotchi Direct Gate Write

## Scope delivered

Five tickets delivered across PRs #71–#75 on branch stack `agents/p17-01` through `agents/p17-05`.

- **P17.01** — `tools/delivery/codogotchi-gate.ts`: `writeGateEvent`, `resolveCodogotchiHome`, `GATE_NAMES` constant, empty-string CODOGOTCHI_HOME guard.
- **P17.02** — Transition gates (`ticket_started`, `ticket_completed`, `red_tdd`, `green_tdd`) wired to `start`, `advance`, `post-red`; `emitSoaEventsForTransitions` retired to no-op.
- **P17.03** — Review-flow gates (`adversarial_review`, `open_pr`, `poll_review`, `record_review`) wired to their handlers; `emitSoaEventForOpenPr` retired; `appendSoaEvent`/`buildSoaEventLine` removed from `cli-runner.ts` imports.
- **P17.04** — `review_clean` gate wired to all three clean-outcome paths; `emitSubagentInvoked` removed; `soa-event-feed.ts` deleted; retired test files cleaned up.
- **P17.05** — `AGENTS.soa.md` updated; product plan status updated; retrospective.

## What went well

**Parallel-then-cutover slice structure held.** Writing the gate writer first (P17.01) with no call-site wiring meant the red test and the module surface were locked before any handler touched them. Later tickets could trust the interface. This is the right decomposition shape for "add a new writer, then replace call sites" — the first ticket is a stable contract, not a prototype.

**Adversarial review caught real gaps every ticket.** Four out of four code tickets had at least one actionable finding:

- P17.01: empty-string `CODOGOTCHI_HOME` not treated as absent.
- P17.02: `emitGateForTransitions` ordering depended on array order (cook-mode invariant silently broken for reversed arrays); `redPolicy === undefined` silently emitted `green_tdd` instead of `red_tdd`.
- P17.03: `openPrTarget` only matched `subagent_review_complete`, silently skipping the gate for `subagentReview=disabled` tickets at `verified` status.
- P17.04: skipped/doc-only fast path for `poll-review` had no negative test.

All four findings were correctness gaps that would have been invisible in a passing test suite. The adversarial review step is earning its keep.

**GATE_NAMES constant added early.** Centralizing gate strings in P17.02 (rather than inline literals) meant P17.03 and P17.04 had zero ambiguity about gate names. No typo drift.

## Pain points

**`emitSoaEventsForTransitions` and `emitSoaEventForOpenPr` needed two-step retirement.** The stubs-before-deletion approach (P17.02/P17.03 make them no-ops; P17.04 deletes them) was necessary because the stubs kept the import chain valid across the stack. The cost was three separate "retired" test file updates. This is expected overhead for a phased NDJSON-to-gate migration — not avoidable, but worth naming as a pattern for future "replace-then-delete" sequences.

**p15-02 and fix-worktree-event-routing test updates required careful wording.** Both test files tested the NDJSON behavior as a positive assertion (`expect(parsed.name).toBe('ticket_started')`). Flipping them to negative assertions (`expect(existsSync(...)).toBe(false)`) is semantically correct but risks a future reader thinking the negative assertion is the real test. Adding comment context ("retired behavior — gate.json handles these events") was the right call.

**`eventRoot` was a hidden coupling.** The `const eventRoot = findPrimaryWorktreePath(...)` line in the CLI handler was only used to route NDJSON writes to the primary worktree. Once all NDJSON calls were retired, the variable became dead. It wasn't immediately obvious that removing it required no other changes — the dead-variable lint error surfaced it cleanly in P17.04.

## Surprises

**`emitSoaEventsForTransitions` iteration order was a correctness gap, not just a style nit.** The cook-mode invariant ("ticket*started is the resident gate after advance") depended on the in_progress ticket appearing \_after* the done ticket in `previousState.tickets`. In practice, tickets are always ordered in delivery sequence, so this was never observed to fail. But it was a latent bug: if any code path ever reordered tickets (e.g., a repair-state command), the wrong gate would persist. The two-pass fix (complete first, start second) made the invariant structural.

**`openPrTarget` lookup was narrower than `openPullRequest`'s internal lookup.** When `subagentReview=disabled`, tickets go directly from `verified` to `open-pr` without touching `subagent_review_complete`. The gate lookup only checked for `subagent_review_complete`, so the `open_pr` gate was silently skipped for this config. This is the kind of gap that emerges when the gate lookup is written independently of the function it gates. Mirror the internal resolution logic.

**Deleting `soa-event-feed.ts` required touching `orchestrator.ts`.** The barrel file re-exported `appendSoaEvent`, `buildSoaEventLine`, `maybeEmitReviewCleanRecorded`, and `SoaEventLine`. These are consumer-facing exports. Any consumer repo that imported from the barrel would break on deletion. In this repo, no consumer existed outside tests (which were already cleaned up). Worth checking barrels before module deletion in any future similar cleanup.

## What we'd do differently

**Start gate constants in P17.01, not P17.02.** `GATE_NAMES` was added in P17.02 because the P17.01 spec focused on the writer module. In practice, the nine gate names are part of the writer's contract — they should have lived in `codogotchi-gate.ts` from the start. P17.02 retroactively added them to the same file, which was fine, but it would have been cleaner to include them in P17.01 where the module was established.

**The "retired behavior" test pattern (positive → negative assertion flip) should have a shared label.** Each of p15-01, p15-02, p15-03 and fix-worktree-event-routing independently got a comment about retired behavior. A shared test-file convention (e.g., a describe block name prefix `(retired — P17.04:`)`) would make it easier to bulk-delete these in a future cleanup pass.

## Net assessment

Phase 17 goals were achieved: `gate.json` receives all 9 gate events at the correct timing, `soa-event-feed.ts` is gone, no command writes to `events.ndjson`, and `codogotchi.enabled: false` produces no `~/.codogotchi/` directory. The adversarial review loop found four real correctness gaps that are now patched. The flat 3m TTL is a deliberate baseline — live gate windows and hook bleed-through behavior remain operator-validated until codogotchi Phase 07 renders `gate.json`.

## Follow-up

- **TTL tuning** — all gates ship at 3m. After codogotchi Phase 07 renders `gate.json`, measure which gates typically expire before the renderer picks them up and adjust per-gate TTL in a follow-up pass. This is not a Phase 17 defect; it is an intended post-delivery calibration.
- **`advance`/`stage_advanced` gate** — deferred in Phase 17 (no hook in `closeout-stack.ts`). When `closeout-stack.ts` is plumbed for gate emission, add the `stage_advanced` gate at that point.
- **Verify `emitSoaEventsForTransitions` and `emitSoaEventForOpenPr` stub removal** — both are no-op stubs retained for backwards-compatible call sites. Confirm no consumer repo imports them before the next subtree sync, then delete both functions in a cleanup PR.
- **Consumer repo migration** — existing consumer repos using Phase 15 installations should remove `.soa/` gitignore entries and any `soa-event-feed` references after updating to the Phase 17 subtree.

_Created: 2026-05-29. PRs #71–#75 open (stacked)._
