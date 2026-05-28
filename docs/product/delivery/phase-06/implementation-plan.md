# Phase 06 — Platform Parity and Attention UX

> Fix stuck-waving, add sticky gate animations, enrich Bash signal, ship Cursor adapter v1, and surface attention bubble on floating pet. Nine tickets, ~20 points, four stage gates.

## Epic

Source product plan: [`docs/product/plans/phase-06-platform-parity-and-attention.md`](../../plans/phase-06-platform-parity-and-attention.md).

## Product contract

When this phase is complete:

- A session ending with `standby` shows the attention bubble, then decays to `idle` after `expires_at` — "stuck waving" is gone.
- SoA gate animations (`hyped`, `calling_for_backup`, `waiting`, `celebrating`) persist for their natural gate-to-gate window; tool_use events no longer stomp them.
- A Cursor session (native or bridge) writes `source_origin: "cursor"` to `state-transitions.log` and shows `implementing` for file edits and shell commands, `reviewing` for shell reads — not `idle` or `claude_code`.
- Bash-heavy sessions (grep/find loops) show `reviewing` in the transition log where they previously showed `idle`.
- Unknown Bash commands show `implementing` instead of `idle`.
- Runbook documents the bridge vs native install paths and when to prefer each.

## Grill-Me decisions locked

- **Q1 — Sticky gate storage:** `last_gate: { state: ActivityState, fired_at: string } | null` stored in `.hook-counters.json` inside the existing lock. Avoids extra `state.json` read per hook invocation. `fired_at` included so Phase 07 can add gate TTL without a counters shape change.
- **Q2 — Schema v3, no compat shim:** `requesting_input → standby` rename + schema version bump. Single user, no migration wizard. Renderer `standby` handling bundled into P6.01 (same PR, same ticket) to eliminate the broken-intermediate-state window.
- **Q3 — Attention summary: fixed strings by `reason_kind`:** Claude Code `Stop` provides only `transcript_path` (extra I/O, hot path). Cursor `stop` provides only `status` enum. Only Codex provides `last_assistant_message` — platform-conditional summaries not worth the complexity for Phase 06. Copy revisited in Phase 07.
- **Q4 — P6.01 bundles contracts + renderer `standby`:** Single PR for the rename. Eliminates the window where `state.json` emits `standby` to a renderer expecting `requesting_input`. Two-language PR is acceptable for single-operator delivery.
- **Q5 — `work_mode` stub in P6.01 schema:** `z.enum(["thinking","implementing","testing"]).optional()`. Phase 07 populates it without a v4 bump. All three values are grounded in real hook events (Cursor `afterAgentThought` confirmed as `thinking` source for Phase 07).
- **Q6 — P6.05 scope includes Cursor shell hooks:** `beforeShellExecution`/`afterShellExecution` are Cursor's Bash equivalents. Apply the same 3-bucket classification path — same ticket as origin fix, different concern from `afterFileEdit`.
- **Retrospective:** `skip` — no operator workflow change, no durable architectural boundary. Phase 07 (SoA direct write) is the boundary worth reviewing.

## Stage Gates

1. **Contracts + renderer locked** — P6.01 merged: schema v3, `standby`, attention type, `work_mode` stub, renderer handles `standby`. All hook PRs unblocked.
2. **Hook signal complete** — P6.02–P6.05 merged: sticky gate, 3-bucket, attention payload, Cursor origin + shell classification.
3. **Cursor adapter done** — P6.06 merged: native installer + bridge docs, `hooks status` shows bridge-vs-native.
4. **Renderer + UI done** — P6.07 + P6.08 merged: TTL policy live, attention bubble visible on floating pet.

## Ticket Order

1. `P6.01 Contract schema v3 + renderer standby`
2. `P6.02 Hook: sticky gate mechanic`
3. `P6.03 Hook: Bash 3-bucket + Cursor Shell normalization`
4. `P6.04 Hook: standby attention payload + tool.command persistence`
5. `P6.05 Cursor adapter: origin fix + shell hooks + workspace_roots`
6. `P6.06 Cursor hooks installer + bridge docs`
7. `P6.07 Renderer TTL policy`
8. `P6.08 Attention bubble UI`
9. `P6.09 Exit validation + doc sweep`

## Ticket Files

- `ticket-01-contract-schema-v3-renderer-standby.md`
- `ticket-02-hook-sticky-gate-mechanic.md`
- `ticket-03-hook-bash-3-bucket-cursor-shell.md`
- `ticket-04-hook-standby-attention-payload-tool-command.md`
- `ticket-05-cursor-adapter-origin-shell-hooks.md`
- `ticket-06-cursor-hooks-installer-bridge-docs.md`
- `ticket-07-renderer-ttl-policy.md`
- `ticket-08-attention-bubble-ui.md`
- `ticket-09-exit-validation-doc-sweep.md`

## Exit Condition

Phase 06 is done when:

1. A manual test session ending with `standby` shows the bubble appear, then decay to `idle` after `expires_at` without any new agent event — "stuck waving" is gone.
2. A live SoA delivery session shows `hyped` and `celebrating` persisting for their natural gate-to-gate window, not flashing for seconds.
3. A Cursor session (native hooks or documented bridge) writes `source_origin: "cursor"` to `state-transitions.log` and shows `implementing` for file edits and `reviewing` for Shell reads — not `idle` or `claude_code`.
4. A Bash-heavy session (grep/find loops) shows `reviewing` in the transition log where it previously showed `idle`.
5. Runbook documents the bridge vs native install paths and when to prefer each.

## CI Baseline

Run `bun run ci:quiet` on `main` before P6.01 starts and record the result here.

> Baseline recorded: [date] — [pass / N pre-existing errors: brief summary]

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- P6.01 is a hard prerequisite for all hook tickets (P6.02–P6.05): the `standby` rename and renderer handling must be merged before any hook changes that emit `standby` land in production.
- P6.06 depends on P6.05: the Cursor installer requires the origin fix and shell hook classification to be in place.
- P6.07 and P6.08 may be delivered in parallel after P6.06 merges.

## Explicit Deferrals

- `work_mode` population (`thinking | implementing | testing`) and animation row remapping — Phase 07.
- `afterAgentThought` (Cursor) as live `thinking` signal — confirmed in hooks docs, Phase 07 scope.
- Full gate vocabulary redesign (`adversarial_prompt_written` timing, `verification_failed` trigger, `stage_advanced` wiring) — Phase 07.
- SoA direct write to `~/.codogotchi/state.json` (eliminates `events.ndjson` tail hop) — Phase 07.
- Richer attention summaries using `last_assistant_message` (Codex) or transcript read — Phase 07.
- Menubar badge count (post-dismiss affordance) — Phase 07.
- Gate TTL auto-expiry in hook counters — Phase 07 (`fired_at` stub is present).

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- Any change to `StateJsonV1` shape beyond what P6.01 specifies — stop and confirm with developer before expanding the contract.
- If `~/.cursor/hooks.json` format differs from what the hooks docs describe, stop before writing the installer (P6.06).

## Phase Closeout

Retrospective: skip
Why: No operator workflow change, no durable architectural boundary introduced. Phase 07 (SoA direct write) is the boundary worth reviewing after it lands.
Trigger: Developer approval of final PR merge.
