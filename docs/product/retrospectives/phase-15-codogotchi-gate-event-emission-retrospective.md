# Phase 15 — Codogotchi Gate Event Emission

## Scope delivered

Phase 15 shipped five code tickets and one docs ticket: event feed writer + config gate ([PR #56](https://github.com/cesarnml/son-of-anton/pull/56)), `ticket_started` / `ticket_completed` emissions ([PR #58](https://github.com/cesarnml/son-of-anton/pull/58)), `pr_review_window_opened` ([PR #59](https://github.com/cesarnml/son-of-anton/pull/59)), `review_clean_recorded` across all three paths ([PR #60](https://github.com/cesarnml/son-of-anton/pull/60)), `subagent_invoked` at pre-spawn ([PR #61](https://github.com/cesarnml/son-of-anton/pull/61)), and this docs + retrospective ticket ([PR #62](https://github.com/cesarnml/son-of-anton/pull/62) — pending closeout).

Delivered surfaces: `tools/delivery/soa-event-feed.ts` (writer module), five emit calls wired in `cli-runner.ts`, `codogotchi.enabled` gate in `orchestrator.config.json` resolution, `AGENTS.soa.md` sidecar documentation, and `notes/public/codogotchi-alignment-draft.md` (cross-repo alignment plan). All four deferred events (`verification_failed`, `risky_diff_detected`, `flow_state_entered`, `stage_advanced`) were explicitly scoped out.

## What went well

**Config gate inside the writer, not at call sites.** Putting the `if (config.codogotchi?.enabled === false) return` check inside `appendSoaEvent` meant every emit call site is a single-line `await appendSoaEvent(config, root, event)` with no conditional wrapping. Future emit additions inherit the gate automatically. The alternative — a boolean flag per call — would require every new call site to re-consult config; putting config itself into the writer made the correct behavior the path of least resistance.

**State-diff helper for `ticket_started` / `ticket_completed`.** Both the `start` and `advance` handlers reduce to a diff of previous vs. next ticket statuses. Extracting `emitSoaEventsForTransitions(previous, next, config, root)` as a shared helper meant the test surface was the diff function, not the two CLI handlers separately. Both callers passed with identical event assertions; no duplication.

**Notification-builder reuse for `review_clean_recorded`.** P15.04's emit helper accepted the `DeliveryNotificationEvent[]` array that the CLI already constructed for Telegram dispatch. Scanning that array for a `review_recorded` event with `outcome === 'clean'` was the smallest correct form — it reused an already-computed shape rather than re-deriving review outcome from state. Three previously independent call sites became symmetric without a shared state reader.

**Filesystem-level integration tests.** All five code tickets exercised their emit paths against real tmp-dir files, not mocks. Each test wrote events, read back the NDJSON file, and parsed the lines. This matches the contract codogotchi consumes — the tests proved format correctness, not just that the function was called.

**P15.02–P15.05 subagent reviews all returned clean.** Once the foundational writer landed, the emit-point tickets had narrow, testable scope. The adversarial pass found no actionable issues in any of the four tickets — a signal that the spec was tight enough that there was little ambiguity at the call sites.

## Pain points

**P15.01 subagent review recorded `skipped`.** The foundational ticket — the writer and gate — had no advisory subagent pass. The codex runner was not available at that moment. This means the most architecturally load-bearing ticket shipped without the cross-family review the subsequent tickets benefited from. Honest `skipped` is better than a fabricated outcome, but the gap is real.

**Rationale sections unfilled in P15.03 and P15.05.** Both tickets shipped with the template stub text unchanged. The rationale section should be completed at `post-verify` time — before `open-pr` — but neither ticket enforced this. This is avoidable waste: the ticket did land correctly, but the `Rationale` section exists precisely so the next phase doesn't have to reconstruct intent from the diff.

**Pre-existing CI baseline failure distracted the phase start.** The `p6-02.test.ts` failure ("notes/public/ contains no .md files") was caused by the codogotchi alignment draft committed in the P15 plan PR. Documenting it in the implementation plan's CI Baseline section was the right call, but it still required reading the CI output carefully at every ticket start to confirm "known failure, not new regression."

## Surprises

**`DeliveryNotificationEvent[]` was already the right shape.** When implementing P15.04, the notification-builder output already contained the `outcome` field needed to detect a clean review. The connection between the Telegram notification path and the event-feed emit path had not been anticipated during planning, but it made `maybeEmitReviewCleanRecorded` a trivial scan rather than a state re-derivation. This pattern — reusing already-computed notification events for the codogotchi feed — is worth carrying into the deferred events when they land.

**The `async` writer did not require any queue or ordering concern.** Because all emit calls are fire-and-forget in otherwise-synchronous CLI handlers, `await appendSoaEvent(...)` runs to completion before the handler continues. There is no concurrent append risk during normal delivery. The `open(..., 'a')` + close-in-finally pattern is sufficient; no stream or mutex was needed.

## What we'd do differently

**Enforce Rationale completion as part of `post-verify`.** The orchestrator currently has no check for unfilled template stubs in ticket rationale sections. A lint step or a simple grep for the `[what test failed first]` template text at `post-verify` time would catch this before a PR opens. The cost is low; the documentation value of filled rationale sections is high, especially for the deferred events when they come back for codogotchi planning.

**Consider a CLI-level integration test for the full dispatch → file assertion chain.** P15.04 explicitly deferred a full-dispatch test ("CLI-level integration test dispatching full handlers and asserting `.soa/events.ndjson` content"). The helper-level tests cover the emit logic, but a coarser test that invokes the actual handler functions and asserts the resulting file content would close the gap between "the helper works" and "the wiring in the handler is correct." This is not a P15 regression — the existing tests are sufficient — but it would reduce the surface left for bugs in future emit-point additions.

## Net assessment

Phase 15's stated goal was to connect the unconnected wire at the SoA end of the codogotchi contract. That goal is achieved: five gate events emit on the correct trigger conditions, the config gate suppresses all writes when disabled, write failures are absorbed silently, and the filesystem tests confirm the NDJSON schema matches what codogotchi reads. The codogotchi hook binary can now receive explicit orchestrator signals for `ticket_started`, `ticket_completed`, `pr_review_window_opened`, `review_clean_recorded`, and `subagent_invoked`. The emit pattern established here is the template all four deferred events will follow.

## Follow-up

- **Codogotchi-side alignment work.** `notes/public/codogotchi-alignment-draft.md` scopes six audit items for the codogotchi repo: hook path resolution, tail semantics integration test, activity state mapping test, precedence rule verification, config gate documentation, and stale-reference audit. This is the natural next phase in the codogotchi repo, feeding off Phase 15 directly.
- **Four deferred events.** `verification_failed`, `risky_diff_detected`, `flow_state_entered`, `stage_advanced` each need a formalized gate point before an emit call can be added. `verification_failed` is the most tractable — it requires capturing the `bun run verify` exit code as a structured result rather than a subprocess pass/fail. Plan that work in the codogotchi alignment phase or a dedicated SoA phase.
- **CLI-level integration test for dispatch → file.** Before adding the next batch of emit points, add at least one coarse test that invokes a full CLI handler and asserts `.soa/events.ndjson` content. Deferred from P15.04.
- **Enforce Rationale completion at `post-verify`.** Add a lint step or template-stub grep to the orchestrator's `post-verify` gate. Assign to EE or a tooling cleanup standalone PR.

---

_Created: 2026-05-23. PRs [#56](https://github.com/cesarnml/son-of-anton/pull/56), [#58](https://github.com/cesarnml/son-of-anton/pull/58), [#59](https://github.com/cesarnml/son-of-anton/pull/59), [#60](https://github.com/cesarnml/son-of-anton/pull/60), [#61](https://github.com/cesarnml/son-of-anton/pull/61), [#62](https://github.com/cesarnml/son-of-anton/pull/62) stacked, pending closeout-stack merge._
