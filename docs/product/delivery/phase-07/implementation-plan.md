# Phase 07 — Signal Honesty and SoA Global Gates

> Retire the events.ndjson tail architecture: the Swift renderer reads a SoA-owned `~/.codogotchi/gate.json` sidecar directly, the hook-binary becomes a pure platform-event classifier, and the ActivityState enum locks to the 19-state schema v4 that all future animation phases build on.

## Epic

Standalone phase. Source product plan: [`docs/product/plans/phase-07-signal-honesty-and-soa-global-gates.md`](../../plans/phase-07-signal-honesty-and-soa-global-gates.md). Producer contract: son-of-anton Phase 17 (`docs/product/plans/phase-17-codogotchi-direct-gate-write.md` in the son-of-anton repo) writes `gate.json`; this phase is the consumer. Locked spec: [`notes/public/phase-06-animation-and-signal-research.md`](../../../notes/public/phase-06-animation-and-signal-research.md) §6–§8.

## Product contract

When this phase is complete:

- The Swift renderer reads `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`) on its poll loop and merges it with `state.json`: an unexpired gate with a sprite row paints its animation instantly (including during agent-idle windows); once `expires_at` passes, hook-driven animation shows through.
- A gate name with no sprite row — unknown (skew) or known-but-artless (`red_tdd`, `green_tdd`, `open_pr`, `record_review` rendered via temporary placeholder rows) — falls through to hook animation; no crash, no gray pet.
- The hook-binary no longer reads `events.ndjson`; it is a pure platform-event classifier writing only `state.json`, emitting the 19-state v4 vocabulary (`reading`/`cramming`/`thinking`/`testing`/`implementing` per research §7).
- `errored` fires on a fixture Claude `StopFailure` and Cursor `stop`+`status:"error"` within one hook invocation.
- `ActivityState` is the 19-state closed schema-v4 enum across contracts, hook-binary, and Swift; `work_mode` and `gate_badge` fields are gone.

## Grill-Me decisions locked

| Decision | Rationale |
| --- | --- |
| P7.01 atomic schema-v4 vocabulary (TS + Swift + fixtures in one ticket) | Coherent enum both sides; avoids a broken intermediate where the hook emits states the renderer refuses (P6.01 precedent) |
| Full §7 hook classifier (`reading`/`cramming`/`thinking`/`testing`/`implementing`) | Enum advertises these states; §7 rules are fully specified; reuses the existing `readRun` streak counter |
| Defer `waiting_for_input`/`PermissionRequest` | Requires new installer surface; "rare in Yolo mode"; enum entry stays for later |
| Swift `GateJsonReader` + standalone merge resolver; no TS Zod schema | Renderer-only reads `gate.json`; a TS schema would have no runtime consumer |
| Renderer reads `gate.json` directly; hook drops all SoA awareness | Instant gates that survive agent-idle windows; one writer per file, no race |
| Render a gate **only if a sprite row exists**; else fall through to hook | One rule covers both unknown-skew gates and known-but-artless gates |
| Temporary placeholder rows on the existing sheet: `green_tdd`→2, `red_tdd`→3, `open_pr`→4, `record_review`→8 | Repurpose retired-state art until `codogotchi-soa-spritesheet.webp` ships; flagged temporary in code + docs |
| 6-tier spritesheet model = documented contract + row-rename only; no multi-sheet loader | Art delivery is deferred per the product plan |
| Drop `work_mode` and `gate_badge` fields | The `gate.json` sidecar + `activity_state` carry the information with a cleaner split |
| Failure parity validated by fixtures; operator validation is the live signal | Matches plan exit 5; no cross-process harness in this phase |

## Ticket Order

1. `P7.01 Schema v4 vocabulary — 19-state enum, drop work_mode, row-map rename + placeholders (TS + Swift)`
2. `P7.02 Hook-binary pure classifier — drop events.ndjson reader, full §7 read/explore buckets`
3. `P7.03 Terminal failure parity — StopFailure + Cursor error classification`
4. `P7.04 Renderer gate.json consumer — GateJsonReader + merge resolver`
5. `P7.05 Phase 07 docs + retrospective`

## Ticket Files

- `ticket-01-schema-v4-vocabulary.md`
- `ticket-02-hook-pure-classifier.md`
- `ticket-03-terminal-failure-parity.md`
- `ticket-04-renderer-gate-json-consumer.md`
- `ticket-05-phase-07-docs-and-retrospective.md`

## Exit Condition

Phase 07 is done when the hook-binary no longer reads `events.ndjson` (pure §7 classifier writing only `state.json`), the Swift renderer reads `gate.json` and merges by `expires_at` (unexpired-gate-with-art wins, expired/artless/unknown falls through to hook, absent gate.json renders pure hook), a fixture Claude `StopFailure` and Cursor `stop`+`status:"error"` each yield `activity_state: "errored"` within one hook invocation, the 19-state schema-v4 `ActivityState` enum is consistent across contracts/hook/Swift with `work_mode` and `gate_badge` removed, and the docs reflect the sidecar architecture and 6-tier model.

## CI Baseline

> Baseline recorded: 2026-05-29 — `bun run ci:quiet` green on `main`: biome clean, TS suite passes, Swift `mac:test` 227 tests / 0 failures. No pre-existing failures.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Gate names consumed here must match the son-of-anton Phase 17 `gate.json` writer contract; no son-of-anton code is touched in this phase.

## Explicit Deferrals

- `waiting_for_input`/`PermissionRequest` hook registration — enum entry stays; wiring deferred to the platform-hooks phase.
- Multi-sheet loader (lite/soa/rpg sheet loading + fallback) and dedicated gate art — Phase 07 locks the enum + tier contract only; placeholder rows are temporary.
- Gate badge UI — `gate.json` carries the context; the floating-pet badge widget is a later phase.
- `advance`/`stage_advanced` gate rendering — son-of-anton Phase 17 does not emit it; enum entry stays.
- Cross-process validation harness — failure parity is fixture-based; live behavior is operator-validated.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope (note: codogotchi CI includes Swift `mac:test`).
- A gate name vs schema-v4 ActivityState mismatch against the son-of-anton Phase 17 contract — confirm against the Phase 17 plan, do not guess.
- A schema-v4 rename surfacing an unanticipated consumer (sync, RPG, fixtures) mid-implementation — escalate rather than widening P7.01 silently.

## Phase Closeout

Retrospective: required
Why: Establishes the durable animation architecture (19-state closed enum, `gate.json` sidecar consumer, renderer-side merge, 6-tier model) that all future animation phases build on; the temporary placeholder rows and flat-3m gate behavior will generate follow-up decisions once real art and delivery data land.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-07-signal-honesty-and-soa-global-gates-retrospective.md`
