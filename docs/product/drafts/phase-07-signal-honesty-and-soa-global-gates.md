# Phase 07 Draft — Signal Honesty and SoA Global Gates

_Drafted: 2026-05-27_
_Updated: 2026-05-28 — architecture decision from Phase 06 planning session_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: [codogotchi-platform-extension-and-signal-pipeline-research.md](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md), [codogotchi-alignment-draft.md](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md), [phase-06-animation-and-signal-research.md](../../notes/public/phase-06-animation-and-signal-research.md)_

---

## Thesis

SoA delivery gates should reach the pet **instantly and directly** — no intermediate file, no dependency on the next hook call. Phase 07 replaces the `events.ndjson` tail architecture with SoA writing directly to `~/.codogotchi/state.json`, and expands the gate vocabulary to cover the full ticket lifecycle.

This phase is **infrastructure** for lite + alive users; it does not require RPG enrollment.

---

## Architecture decision (resolved in Phase 06 planning)

**SoA writes directly to `~/.codogotchi/state.json`** on gate emit. The `events.ndjson` tail reader in `hook-binary.ts` is retired. No backward-compat bridge needed (single user until v1).

**Why:** The tail architecture meant gate animations only fired on the next tool_use invocation — often seconds after the gate — and were immediately overwritten by the following tool_use. Real gate-to-gate windows are 8–20 minutes for `hyped`, hours for `celebrating`. The intermediate file hop was pure latency with no benefit. SoA already knows `~/.codogotchi/` exists (it invokes the hook binary). See [phase-06-animation-and-signal-research.md](../../notes/public/phase-06-animation-and-signal-research.md) for the full log analysis.

**Phase 06 ships a sticky gate interim fix** (gates persist until next gate or session_end). Phase 07 makes it architectural.

---

## The problem (updated)

- SoA gate animations were invisible in practice: `hyped` median actual duration was 5s (stomped by tool_use) vs 8.3m gate-to-gate window. Four of nine gate→state mappings never fired in 6 days of real delivery data (`focused`, `nervous`, `ascended`, `panicking`, `errored`).
- Gate vocabulary doesn’t cover the full ticket lifecycle: no `adversarial_prompt_written` (currently misfires on subagent start), no `verification_failed` trigger in practice, `stage_advanced`/`ascended` never fires.
- `work_mode` stub (Phase 06) needs taxonomy and animation row mapping.

---

## Committed scope (Codogotchi repo)

### 1. SoA direct write consumer

- Hook `runHook()` no longer reads `.soa/events.ndjson` tail
- SoA writes `state.json` directly; hook handles tool_use + session_end only
- Gate TTL: 30s minimum — tool_use cannot overwrite a gate state younger than TTL (prevents stomping during rapid agent activity immediately after a gate)
- `work_mode` field populated from 3-bucket Bash heuristic (Phase 06 adds stub; Phase 07 wires it)

### 2. Full gate vocabulary

Updated gate → animation mapping covering the real ticket lifecycle:

| Gate | Animation | Lifecycle moment |
|---|---|---|
| `ticket_started` | `hyped` | Ticket begins |
| `adversarial_prompt_written` | `calling_for_backup` | Adversarial prompt committed (not subagent start) |
| `verification_failed` | `panicking` | Verify step fails |
| `pr_review_window_opened` | `waiting` | AI review in progress |
| `review_clean_recorded` | `celebrating` | Review passed |
| `stage_advanced` | `ascended` | Stack slice merged |
| `ticket_completed` | `celebrating` | Ticket done |

Retire or repurpose `subagent_invoked` (misfired timing), `flow_state_entered`, `risky_diff_detected` — these never fired in real delivery; evaluate before wiring.

### 3. `work_mode` taxonomy

- `work_mode: thinking | implementing | testing` written to `state.json`
- Animation row remapping: decide which codogotchi sheet rows to retire/repurpose (`panicking` row 6, `focused` row 2 — both zero-fire candidates) for `thinking` and richer `implementing` vocabulary
- See [phase-06-animation-and-signal-research.md](../../notes/public/phase-06-animation-and-signal-research.md) for spritesheet row inventory

### 4. Transition log v2 fields

- `tool_command`, `work_mode`, `platform` on state change lines
- `platform` reflects actual agent surface (not bridge heuristic default)

### 5. Menubar badge count

- Post-dismiss attention count badge on the menubar icon
- Evaluate interaction pattern after Phase 06 floating bubble ships

---

## Committed scope (Son-of-Anton upstream)

_Deliver in `~/code/son-of-anton` as a separate plan/phase; codogotchi draft tracks dependency._

- SoA `deliver` writes gate events directly to `~/.codogotchi/state.json` (not `gate-events.ndjson`)
- `adversarial_prompt_written` gate fires when prompt is written to review artifact, not on subagent process start
- Document in SoA `AGENTS.md`

---

## Defers

- VS Code / Antigravity adapters → **Phase 14**
- Premium SoA animation entitlement → **Phase 13**
- Spritesheet expansion (new rows for `thinking`, richer `idle` states) → tracked in [phase-06-animation-and-signal-research.md](../../notes/public/phase-06-animation-and-signal-research.md)

---

## Exit conditions

1. SoA `deliver` in a consumer repo writes directly to `~/.codogotchi/state.json` — no events.ndjson intermediate.
2. `hyped` persists visibly for its full gate-to-gate window during a live delivery session.
3. `adversarial_prompt_written` gate fires at prompt-write time; `subagent_invoked` retired.
4. `work_mode` field appears in `state.json` for Bash events.

---

## Dependencies

- **Phase 06** sticky gate mechanic (interim fix) must land first
- **SoA upstream** direct write can land in parallel if contract is frozen first

---

## Next step

`/soa plan docs/product/drafts/phase-07-signal-honesty-and-soa-global-gates.md`
