# Codogotchi Alignment Draft Plan

## Bring codogotchi into full alignment with SoA Phase 15 gate event emission

_Drafted: 2026-05-23_
_Status: Draft — not yet through `/soa plan` in the codogotchi repo_
_Cross-reference: [son-of-anton Phase 15 plan](../../docs/product/plans/phase-15-codogotchi-gate-event-emission.md)_

---

## Context

Son-of-Anton Phase 15 ships the write path for `.soa/events.ndjson`. The codogotchi hook binary has always been built to read that file, but SoA never wrote to it — so Mali has never entered any orchestrator-specific animation state (`hyped`, `celebrating`, `waiting`, `calling_for_backup`, etc.).

After Phase 15 ships, SoA will emit five gate events at recognized delivery boundaries. Codogotchi's contract documents (`docs/contracts/soa-event-feed.md`, `packages/contracts/src/soa-events.ts`) are already schema-correct. This plan covers what codogotchi still needs to do on its side to complete the circuit and verify end-to-end behavior.

---

## What the contract already has (no changes needed)

- `soa-events.ts` — `SOA_EVENT_NAMES` includes all 9 events; `SOA_EVENT_TO_ACTIVITY_STATE` mapping is correct.
- `soa-event-feed.md` — line schema, tail semantics, precedence rule, and producer/consumer boundary are all accurate.
- `animation-state-vocabulary.md` — SoA-sourced rows are documented.

These do not need to change for the five Phase 15 events. New SoA events will require a row added here when they land.

---

## Full audit scope (what this plan covers)

### 1. Hook binary path resolution audit

Verify the hook binary's `$CLAUDE_PROJECT_DIR` / `$CODEX_PROJECT_DIR` / cwd resolution logic against the current behavior of Claude Code and Codex CLI. Specifically:

- Confirm `$CLAUDE_PROJECT_DIR` is set by the current Claude Code hook invocation environment (Claude Code version at time of Phase 15 ship).
- Confirm `$CODEX_PROJECT_DIR` is set by current Codex CLI hook invocation.
- Confirm the cwd fallback fires correctly when neither env var is set (e.g., manual hook invocations or test harness runs).
- Document the resolution order in an integration test — not just a contract doc assertion.

**Risk:** Claude Code or Codex CLI may have changed env var names or semantics since the hook was originally written. If the hook resolves to the wrong project root, it will either miss `.soa/events.ndjson` entirely or read the wrong project's file.

### 2. Inode tracking and tail semantics integration test

The hook tracks `(inode, offset)` in a per-home sidecar. The current tests likely mock this or test it in isolation. Add an end-to-end test that:

- Creates a real `.soa/events.ndjson` file with SoA-shaped lines.
- Invokes the hook binary multiple times, simulating incremental appends.
- Verifies that each invocation only processes lines appended since the last read (no re-processing, no missed lines).
- Tests the inode-change reset path (file truncated or recreated).
- Tests the partial-line guard (no `\n` terminator on the last line — must not consume).

**Risk:** The tail logic is subtle. A bug here means Mali either replays old events on every hook call or silently skips new ones — both are invisible until a developer notices the animation is wrong.

### 3. Activity state mapping integration test

Add a test that:

- For each of the five Phase 15 events (`ticket_started`, `ticket_completed`, `pr_review_window_opened`, `review_clean_recorded`, `subagent_invoked`), writes a valid event line to a temp `.soa/events.ndjson`.
- Invokes the hook logic (or the mapping function directly) and asserts the correct `activity_state` is returned.
- Verifies that an unknown `name` field does not override the tool-call heuristic (passthrough behavior).
- Verifies that a malformed line (non-JSON, missing required field) is silently skipped without throwing.

**Risk:** The `mapSoaEventToActivityState` function exists and is correct, but it may not be exercised with a real file read in any current test. Mocking the parse is not sufficient — the full read→parse→map pipeline should be tested.

### 4. Precedence rule verification

The contract says: "The latest fresh SoA event wins for `activity_state` when a fresh SoA event and a Claude/Codex tool-call event occur in the same hook invocation." Verify:

- A fresh `ticket_started` SoA event overrides a `bash` tool-call heuristic in the same step.
- An unrecognized SoA event name does NOT override the tool-call heuristic.
- When no fresh SoA events exist, tool-call heuristics drive `activity_state` normally.

### 5. `orchestrator.config.json` codogotchi gate documentation

SoA Phase 15 adds an optional `codogotchi: { enabled: boolean }` field to `orchestrator.config.json`. When `enabled: false`, SoA writes no events. Document this in:

- `docs/contracts/soa-event-feed.md` — add a producer-side note: "If the events file is absent or stops growing, check that `codogotchi.enabled` is not set to `false` in the SoA consumer repo's `orchestrator.config.json`."
- Any codogotchi setup/troubleshooting guide.

### 6. `animation-state-vocabulary.md` stale-reference audit

Review `docs/contracts/animation-state-vocabulary.md` for any SoA command names or CLI invocations that reference old SoA commands (pre-Phase 12). SoA has evolved significantly (phases 1–15). Stale references in this doc will mislead consumers who look to it for SoA integration guidance.

Specifically check:

- Any mention of SoA CLI commands that no longer exist or have been renamed.
- Any assumed SoA state machine transitions that no longer match the current `TicketStatus` type.
- Any animation trigger descriptions that reference codogotchi-internal logic that should now be superseded by the SoA event feed.

---

## Suggested delivery approach for codogotchi

This plan targets a single focused phase in the codogotchi repo:

| #   | Title                                              | Scope               |
| --- | -------------------------------------------------- | ------------------- |
| 01  | Path resolution + tail semantics integration tests | Items 1 and 2 above |
| 02  | Activity state mapping + precedence tests          | Items 3 and 4 above |
| 03  | Config gate doc + stale-reference audit            | Items 5 and 6 above |

---

## Cross-repo traceability

- SoA emit contract: `docs/contracts/soa-event-feed.md` in codogotchi repo
- SoA Phase 15 implementation plan: `docs/product/delivery/phase-15/implementation-plan.md` in son-of-anton repo (once decomposed)
- This draft: `notes/public/codogotchi-alignment-draft.md` in son-of-anton repo

When Phase 15 ships, the final ticket doc (`P15.05` or whichever covers docs) should link to this file. The codogotchi phase retrospective should reference the SoA Phase 15 retrospective.
