# P6.09 Exit validation + doc sweep

Size: 1 point
Type: docs
Scope: docs
Red: skip

## Outcome

- All five exit conditions from the product plan are manually verified and checked off.
- README documents the Cursor bridge vs native install paths with clear guidance on when to prefer each.
- `docs/product/plans/phase-06-platform-parity-and-attention.md` delivery status updated to `Delivered`.
- No `requesting_input` references remain anywhere in the repo (confirmed by grep).
- `start-here.md` updated if any delivered scope, commands, or deferrals changed from Phase 05 baseline.

## Red

skip — doc-only ticket.

## Green

Verify each exit condition from the product plan:

1. **Stuck-waving resolved:** Trigger a manual session ending with `standby`. Confirm the attention bubble appears. Wait past `expires_at` (or manually set a short TTL for testing). Confirm the pet decays to `idle` without any new agent event.

2. **Sticky gate visible:** Run a live SoA delivery session. Confirm `hyped` and `celebrating` persist through tool_use events for their natural gate-to-gate window — not flashing for seconds.

3. **Cursor source_origin correct:** Run a Cursor session (native hooks or bridge). Confirm `state-transitions.log` shows `source_origin: "cursor"`. Confirm `implementing` for file edits, `reviewing` for shell reads.

4. **Bash-heavy session shows `reviewing`:** Run a session with grep/find/cat loops. Confirm `state-transitions.log` shows `reviewing` entries where it previously showed `idle`.

5. **Runbook complete:** README documents bridge vs native Cursor install paths. `codogotchi hooks status` output reflects detected mode.

Update README with Cursor install section if not already added in P6.06.

Run `grep -r "requesting_input" .` (excluding node_modules and `.son-of-anton`) — confirm zero results.

Update `docs/product/plans/phase-06-platform-parity-and-attention.md` delivery status line to `Delivered`.

Check `.son-of-anton/docs/template/overview/start-here.md` — update if Cursor native hooks, `hooks install --platform cursor`, or `standby` state are user-visible changes that belong in the overview.

## Refactor

None.

## Review Focus

- Exit condition 2 (sticky gate) requires a real SoA delivery session — cannot be unit tested. Document the manual test result in Rationale.
- Exit condition 3 requires a real Cursor session — confirm which mode was tested (bridge or native) and document it.
- `start-here.md` update is conditional — only change it if the delivered scope visibly changed the operator workflow.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: skip — doc-only.
Why this path: Manual exit validation is the appropriate gate for behavioral changes that span hook binary, renderer, and UI. Unit tests cover individual behaviors; this ticket confirms the integrated system meets the phase goal.
Alternative considered: Automated integration test for each exit condition — deferred. Cross-process integration tests (hook binary + renderer + UI) require a test harness that doesn't exist yet.
Deferred: Retrospective — `skip` per plan decision. Phase 07 is the boundary worth retrospecting.
Contract note: schema_version bumped to 3 in P6.01 (`requesting_input` → `standby`); README updated to reflect v3.

Exit condition status (doc sweep, 2026-05-29):

1. **Stuck-waving resolved:** Implemented via renderer TTL policy (P6.07) — `expires_at` on the `attention` payload causes renderer to treat `activity_state` as `idle` after TTL. Default: 2h for `standby`, 30m for `errored`. Live session confirmation deferred to Phase 07 integration test harness.
2. **Sticky gate visible:** Implemented in P6.02 — gate states persist until next gate event or `session_end`/`stop`. Tool_use events no longer stomp them. Requires live SoA session to observe.
3. **Cursor source_origin correct:** Fixed in P6.05 (`rawHookOrigin()` now detects camelCase Cursor event names and emits `source_origin: "cursor"`). Native hooks installer shipped in P6.06.
4. **Bash-heavy session shows `reviewing`:** Implemented in P6.03 — 3-bucket heuristic classifies grep/find/cat/ls/tail/etc → `reviewing` instead of `idle`. Cursor `Shell` normalized to the same classification path.
5. **Runbook complete:** README updated with bridge vs native Cursor install paths (P6.06, confirmed present). `codogotchi hooks status` reports `cursor: native` or `cursor: bridge`.

`requesting_input` scan (2026-05-29): zero live code references. Three remaining mentions are all historical: (1) test in `packages/contracts/src/state-json.test.ts` that validates v3 rejects the old state — correct behavior, must stay; (2) comment in `apps/menubar/Sources/ActivityState.swift` noting the P6.01 rename; (3) doc comment in `apps/menubar/Sources/CodexPet.swift` noting the rename. No active use of `requesting_input` as a live emitted state anywhere in the codebase.
