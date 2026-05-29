# Phase 17 — Codogotchi Direct Gate Write

> Retire the `events.ndjson` append writer and have SoA write delivery gate events to a SoA-owned `~/.codogotchi/gate.json` sidecar with correct emit-then-action timing and per-gate TTLs — the hard prerequisite for codogotchi Phase 07.

## Epic

Standalone phase. Source product plan: [`docs/product/plans/phase-17-codogotchi-direct-gate-write.md`](../../plans/phase-17-codogotchi-direct-gate-write.md). Consumer contract: codogotchi Phase 07 (`docs/product/plans/phase-07-signal-honesty-and-soa-global-gates.md` in the codogotchi repo) — gate names written here are the codogotchi schema-v4 ActivityState values; the codogotchi Swift renderer reads `gate.json` directly.

## Product contract

After Phase 17 ships, running delivery commands writes the current gate to `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`) — a single global file SoA owns exclusively — within the same command invocation:

- `deliver start <ticket>` → `ticket_started` at entry; at exit, `red_tdd` (`Red: required`) or `green_tdd` (`Red: skip`)
- `deliver advance` (cook-mode auto-start of next ticket) → `ticket_started`; (transition to `done`) → `ticket_completed`
- `deliver post-red` → `green_tdd`
- `deliver write-subagent-adversarial-review` → `adversarial_review`
- `deliver open-pr` → `open_pr`
- `deliver poll-review` → `poll_review`
- `deliver record-review` → `record_review`; clean outcome (record/poll/triage) → `review_clean`

Each `gate.json` is `{ gate, since, expires_at, plan_key, ticket_id }` with a flat 3-minute TTL (`expires_at = since + 3m`). All writes are best-effort: a write failure never aborts a delivery command. `codogotchi.enabled: false` in `orchestrator.config.json` suppresses all writes — no `~/.codogotchi/` directory is created. Gates are emitted **before** their action ("emit then action") to extend the effective animation window.

## Grill-Me decisions locked

| Decision                                                                                | Rationale                                                                                                                     |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 9 emitted gates; only `advance`/`stage_advanced` deferred                               | No emit hook in `closeout-stack.ts`; lowest-value gate (2m beat)                                                              |
| `ticket_started` at `start` entry + transition-driven for cook-mode auto-start          | Keeps the entry beat; reuses existing `emitSoaEventsForTransitions` diff                                                      |
| `start` exit branches on `Red:` — `required`→`red_tdd`, `skip`→`green_tdd`              | Every ticket gets a phase gate; no implement window left to hook-only                                                         |
| `green_tdd` also fires on `post-red` (Red: required path)                               | Two anchors, one meaning ("now implementing"); name avoids hook-bucket `implementing` collision                               |
| No synthetic `ticket_started` on mid-ticket resume                                      | Hook layer shows honest `thinking`/`reading` during orientation; no new command surface, no skill-level emit                  |
| `gate.json` = `{ gate, since, expires_at, plan_key, ticket_id }`                        | Deferred badge UI + `state-transitions.log` auditing need ticket context; zero derivation cost (emit sites already hold them) |
| Global file at `$CODOGOTCHI_HOME` (default `~/.codogotchi/`); drop projectRoot plumbing | One pet shows one current gate; renderer reads one path                                                                       |
| No explicit `gate.json` clear (YAGNI)                                                   | `expires_at` handles animation staleness; a clear trigger doesn't naturally exist in the CLI                                  |
| Flat 3m TTL all gates                                                                   | Explore hook bleed-through; tune per-gate later from `state-transitions.log`                                                  |
| Parallel-then-cutover; delete `soa-event-feed.ts` last                                  | Small reviewable slices; harmless mixed-output intermediate (no consumer reads either file until codogotchi Phase 07)         |
| Per-ticket filesystem tests (tmp `CODOGOTCHI_HOME`); no smoke ticket                    | Matches Phase 15; gates are independent handlers; `gate.json` is last-write-wins with little emergent sequencing              |
| Emit-then-action tested by content, not strict ordering                                 | "Emit first" is a code-structure guarantee enforced at review; process-timing assertions are brittle                          |
| `subagent_invoked` retired entirely                                                     | Misfire timing; replaced by `adversarial_review` at write-prompt time                                                         |

## Ticket Order

1. `P17.01 Add codogotchi-gate.ts gate.json writer + CODOGOTCHI_HOME resolution`
2. `P17.02 Cut over transition gates + red_tdd/green_tdd start-exit branch`
3. `P17.03 Cut over review-flow gates with emit-then-action`
4. `P17.04 Cut over review_clean, retire subagent_invoked, delete soa-event-feed.ts`
5. `P17.05 Phase 17 docs + retrospective`

## Ticket Files

- `ticket-01-codogotchi-gate-writer-and-home-resolution.md`
- `ticket-02-cutover-transition-gates-and-tdd-branch.md`
- `ticket-03-cutover-review-flow-gates.md`
- `ticket-04-cutover-review-clean-retire-subagent-invoked-delete-old-writer.md`
- `ticket-05-phase-17-docs-and-retrospective.md`

## Exit Condition

Phase 17 is done when running the delivery commands writes the correct `{ gate, since, expires_at, plan_key, ticket_id }` to `$CODOGOTCHI_HOME/gate.json` (verifiable by `cat` without codogotchi installed), `expires_at == since + 3m`, gates emit before their action, `codogotchi.enabled: false` produces no `~/.codogotchi/` directory, all delivery commands exit zero even when the write would fail, `subagent_invoked` is gone, `soa-event-feed.ts` and `events.ndjson` emission are removed, and `AGENTS.soa.md` documents the `gate.json` sidecar.

## CI Baseline

> Baseline recorded: 2026-05-29 — `bun run ci:quiet` green except 1 pre-existing Prettier formatting warning on `.agents/skills/preflight/SKILL.md` (unrelated to this phase; resolved by `bun run format`). Test suite passes.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- The codogotchi-side renderer consumer is out of scope — gate names must match the codogotchi schema-v4 ActivityState contract but no codogotchi code is touched here.

## Explicit Deferrals

- `advance`/`stage_advanced` gate emission — no hook in `closeout-stack.ts`; defined in the codogotchi enum but not emitted.
- `red_tdd` is emitted (start-exit, `Red: required`); no new `deliver` command is added for any gate.
- Gate badge UI and the codogotchi renderer merge — codogotchi Phase 07 scope.
- Per-gate TTL tuning — all gates ship at flat 3m; adjustment is a post-delivery operational task.
- Explicit `gate.json` clearing on completion/session-end — relies on `expires_at` + next-gate overwrite.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- A gate with no coherent command/transition anchor surfacing mid-implementation (escalate rather than inventing command surface).
- Ambiguity about a gate name vs the codogotchi schema-v4 contract — confirm against the codogotchi Phase 07 plan, do not guess.

## Phase Closeout

Retrospective: required
Why: Establishes the durable gate-emission architecture (sidecar model, 8-gate vocabulary, emit-then-action timing, TTL semantics, `CODOGOTCHI_HOME` resolution) and retires the Phase 15 NDJSON writer. The flat 3m TTL is a deliberate starting guess; real delivery data will drive follow-up tuning.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-17-codogotchi-direct-gate-write-retrospective.md`
