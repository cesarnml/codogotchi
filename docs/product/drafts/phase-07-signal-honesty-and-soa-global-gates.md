# Phase 07 Draft — Signal Honesty and SoA Global Gates

_Drafted: 2026-05-27_
_Updated: 2026-05-29 — platform hook research; **Inputs for `/soa plan`** section_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: [codogotchi-platform-extension-and-signal-pipeline-research.md](../../notes/public/codogotchi-platform-extension-and-signal-research.md), [codogotchi-alignment-draft.md](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md), [phase-06-animation-and-signal-research.md](../../notes/public/phase-06-animation-and-signal-research.md)_

---

## Inputs for `/soa plan`

**Command:** `/soa plan docs/product/drafts/phase-07-signal-honesty-and-soa-global-gates.md`

`/soa plan` writes **`docs/product/plans/phase-07-signal-honesty-and-soa-global-gates.md`** only (what/why). No tickets — that is `/soa decompose` after approval. Grill-me stays **product-level** (goals, ships, defers, exit conditions, risks); defer Zod fields and ticket breakdown to decompose.

**Naming:** This is **Codogotchi** Phase 07 (signal honesty). The Son-of-Anton repo has a separate Phase 07 (runtime delivery policy) — call out **codogotchi vs SoA upstream** work in the product plan.

### Tier 1 — must read (plan input)

| Document | Role |
| --- | --- |
| This draft | Primary seed: thesis, scope, platform hooks, exit conditions |
| [phase-06-platform-parity-and-attention.md](../plans/phase-06-platform-parity-and-attention.md) | Phase 06 **deferrals into P7** (direct write, gate redesign, `work_mode`, animation remap) |
| [phase-06-animation-and-signal-research.md](../../notes/public/phase-06-animation-and-signal-research.md) | Locked spec: §4 gates, §5 SoA architecture, §6–§8 spritesheet tiers, closed enum |
| [phase-05-through-14-roadmap-index.md](./phase-05-through-14-roadmap-index.md) | Ladder: P7 vs P8 (lite v1 gate), P9+, P13, P14 |

After Phase 06 merges, also read:

| Document | Role |
| --- | --- |
| [phase-06/implementation-plan.md](../delivery/phase-06/implementation-plan.md) | Grill-me decisions (sticky `last_gate`, schema v3, interim `reviewing` → superseded in P7) |
| Phase 06 plan **Exit condition** | Preconditions: sticky gates, Cursor parity, attention TTL |

### Tier 2 — grill-me context

| Document | Role |
| --- | --- |
| [codogotchi-platform-extension-and-signal-pipeline-research.md](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md) | Extension / signal pipeline model |
| [codogotchi-alignment-draft.md](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md) | SoA upstream: gate emit, direct `state.json` write |
| [animation-state-vocabulary.md](../../contracts/animation-state-vocabulary.md) | Current contract (stale vs research) — plan commits to bump, not field design |
| [soa-event-feed.md](../../contracts/soa-event-feed.md) | Contract P7 retires (`.soa/events.ndjson` tail) |
| [codex-native-pet-animation-triggers.md](../../notes/public/codex-native-pet-animation-triggers.md) | Codex row semantics (e.g. row 6 ≠ SoA `poll_review`) |
| [phase-05-14-ship-it-merge.md](../../notes/public/phase-05-14-ship-it-merge.md) | Scope guardrails: P7 hard value only |

### Tier 3 — cross-repo (plan dependency, separate SoA plan)

- **son-of-anton:** direct write on gate emit, gate name/timing fixes (`write-subagent-adversarial-review`, etc.)
- **codogotchi:** `orchestrator.config.json` (`codogotchi.enabled`), `AGENTS.md` event sidecar notes

### Tier 4 — decompose only (not product-plan prose)

Link from plan **Dependencies**; detail in tickets: `packages/contracts/src/animation-state.ts`, `soa-events.ts`, `packages/cli/src/hook-binary.ts`, Swift renderer / pet sheets. Log evidence is summarized in research §1 — raw `state-transitions.log` not required for plan.

### Plan approval checklist

The approved `docs/product/plans/phase-07-*.md` should commit to:

1. SoA **direct write** to `~/.codogotchi/state.json`; hook drops NDJSON tail reader
2. **Gate vocabulary** aligned with real orchestrator lifecycle (incl. `adversarial_review`, `poll_review`, TDD gates)
3. **Schema bump** + closed enum (`testing`, `thinking`, `reading`, `cramming`, renames; drop `reviewing`, old gate names)
4. **Three-tier spritesheet** resolution (Codex fallback, lite, SoA sheet) per research §6–§8
5. **Terminal failure parity** (`errored`) on Claude / Cursor / Codex
6. **`work_mode`** populated where hooks are reliable
7. **Depends on Phase 06** (sticky gate, schema v3, Cursor installer)
8. **Defers:** RPG `celebrating` / `ascended`, Phase 14 platforms, Phase 13 premium pack; menubar badge optional

**Grill-me prompt (paste):** Plan Phase 07 from this draft. Cross-check Phase 06 plan deferrals and research §4–§8. Product level only: goals, ships, defers, exit conditions, codogotchi vs SoA upstream split. No tickets or Zod field design.

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

## Platform hook research — failure → `errored` (2026-05-29)

Sources: [Claude Code hooks](https://code.claude.com/docs/en/hooks) (prior read), [Cursor hooks](https://cursor.com/docs/hooks), [Codex hooks](https://developers.openai.com/codex/hooks). Symptom that motivated this section: Claude Code rate limit left Maew stuck on `implementing` — last transition was `tool_use` / `Bash` with no terminal failure hook.

### Claude Code (current gap — confirmed)

| Event | When | Codogotchi today | Phase 07 action |
| --- | --- | --- | --- |
| **`Stop`** | Turn ends normally (awaiting user) | Registered | `requesting_input` (unchanged) |
| **`StopFailure`** | Turn ends due to **API error** — runs **instead of** `Stop` | **Not registered** | **Register + classify → `errored`** |

`StopFailure` payload (authoritative): `hook_event_name: "StopFailure"`, `error` ∈ `rate_limit`, `authentication_failed`, `oauth_org_not_allowed`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `unknown`; optional `error_details`, `last_assistant_message` (rendered API error text). Output/exit code ignored (notification-only).

**Do not** rely on `Stop` + `is_error` for rate limits — API failures do not take the `Stop` path. `Stop` + `stop_reason: "max_tokens"` remains a valid `errored` path for truncation, separate from `StopFailure`.

Installer change: add `StopFailure` to `CODOGOTCHI_EVENTS` in `packages/cli/src/hooks.ts` (alongside `PreToolUse`, `Stop`).

### Cursor (native hooks)

Cursor uses **camelCase** `hook_event_name` values; config at `~/.cursor/hooks.json` or `.cursor/hooks.json`. Agent loop events relevant to Codogotchi:

| Event | Failure / terminal signal | Map to |
| --- | --- | --- |
| **`stop`** | `status: "completed" \| "aborted" \| "error"` | `"error"` → **`errored`**; `"completed"` → `requesting_input`; `"aborted"` → `idle` or `standby` (decide in plan) |
| **`postToolUseFailure`** | Tool fail / timeout / deny: `failure_type`, `error_message`, `is_interrupt` | **`errored`** when not `is_interrupt` (or always clear implementing — tune in plan); do not treat as `implementing` |
| **`subagentStop`** | `status: "error"` | **`errored`** or gate-specific (lower priority than turn-level `stop`) |
| **`sessionEnd`** | `reason: "error"` + optional `error_message` | **`errored`** (fire-and-forget; good backstop if `stop` missed) |
| **`afterAgentThought`** | `{ text, duration_ms }` | **`work_mode: thinking`** (Phase 06 defer; not failure) |

**No `StopFailure` event** in Cursor docs — failure is expressed on native `stop` / tool-failure hooks, not Claude’s split Stop/StopFailure model.

**Cloud agents:** Cursor docs list `stop`, `afterAgentResponse`, `afterAgentThought` as **not yet wired** for cloud agents — `errored` via `stop` will not fire in cloud until Cursor ships it. Document in parity matrix.

**Third-party Claude bridge:** Cursor can load hooks from Claude Code config (`~/.claude/settings.json`). Whether `StopFailure` fires through that bridge is **unverified** — Phase 07 should add a fixture or manual runbook step; native `stop` + `status: "error"` is the Cursor-owned backstop once P6 native installer lands.

**Env:** `CURSOR_PROJECT_DIR`, `CURSOR_TRANSCRIPT_PATH` documented; use for SoA root + optional richer attention copy (Phase 07 attention item).

### Codex

Public Codex hook surface (2026-05-29): `SessionStart`, `SubagentStart`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStop`, `Stop`. **No `StopFailure` or `PostToolUseFailure` in Codex docs.**

| Event | Notes for Phase 07 |
| --- | --- |
| **`Stop`** | `last_assistant_message` may contain error text when turn fails; `matcher` ignored. Classifier today only handles `hook_event_name === "stop"` for `requesting_input` / `is_error` — **Codex rate-limit path needs explicit discovery** (fixture from real `Stop` on API error, or transcript scrape). |
| **`PostToolUse`** | Normal success path; hook script failure is reported by Codex but is **hook infrastructure failure**, not agent API failure — do not conflate with `errored`. |

Codex install today: `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop` — sufficient **if** `Stop` carries failure semantics; insufficient if failures are only visible outside `Stop`.

### Cross-platform installer + classifier matrix (proposed)

| Platform | Events to register (additions in **bold**) |
| --- | --- |
| Claude Code | `PreToolUse`, `Stop`, **`StopFailure`** |
| Codex | `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop` (unchanged until Codex documents failure event) |
| Cursor native | `preToolUse`, `postToolUse`, **`postToolUseFailure`**, `afterFileEdit`, `beforeShellExecution` / `afterShellExecution`, **`stop`**, optional **`sessionEnd`** |

Classifier (`hook-binary.ts`): add branches **before** generic `tool_use` heuristics (same tier as existing `Stop` / `is_error`):

1. `hook_event_name` ∈ `StopFailure`, `stopfailure` → `errored` (+ persist `error` in transition log v2 / `source_event.name` if useful).
2. Cursor `stop` + `status === "error"` → `errored`.
3. Cursor `postToolUseFailure` + `!is_interrupt` → `errored` (exact rule TBD).
4. Keep SoA direct-write gate precedence **above** all of the above when upstream lands.

### Tie-in to Phase 07 committed scope

- Adds a **sixth workstream** (or expands §1 hook consumer): **terminal failure hook parity** so `errored` is observable on all lite platforms, not only synthetic `is_error` / `max_tokens` on Claude `Stop`.
- Explains why `errored` never fired in 6 days of delivery data alongside gate stomping — rate limits never reached the hook.
- **`work_mode: thinking`**: wire Cursor `afterAgentThought` (confirmed in Cursor docs).
- **Transition log v2**: include platform-native failure fields (`error`, `status`, `failure_type`) when present on stdin.
- **Exit condition candidate:** During a forced rate limit (Claude) or `stop`/`postToolUseFailure` error (Cursor), `activity_state` becomes `errored` within one hook invocation and does not remain `implementing` after heartbeats.

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
