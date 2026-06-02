# Phase 07: Signal Honesty and SoA Global Gates

**Delivery status:** Product plan approved (revised 2026-05-29 to align with son-of-anton Phase 17 sidecar architecture). Pending decomposition.

## TL;DR

**Goal:** Replace the `events.ndjson` tail architecture with SoA writing gate events to a dedicated `~/.codogotchi/gate.json` sidecar that the Swift renderer reads directly — so gate animations show instantly and persist for their window — expand the gate vocabulary to the real ticket lifecycle, and lock the closed ActivityState enum and 6-tier spritesheet user model that all future animation phases build on.

**Ships:**
- **Sidecar consumer:** Swift renderer reads `~/.codogotchi/gate.json` directly, merges with `state.json`, resolves precedence by `expires_at`. Hook-binary drops **all** SoA awareness — pure platform-event classifier
- Schema v4: 19-state closed ActivityState enum (9 hook/lite/Codex + 10 SoA gate states); 12 states deleted, renamed or added — authoritative spec: `notes/public/phase-06-animation-and-signal-research.md §8`
- Gate animation precedence: an unexpired gate in `gate.json` wins over hook state; after `expires_at` passes, hook-driven animations bleed through (gate context survives in `gate.json` for a future badge UI)
- Full gate vocabulary aligned with real ticket lifecycle; TDD gates and micro-gates defined in enum, activate as son-of-anton Phase 17 emits them
- Terminal failure hook parity: Claude `StopFailure` registered; Cursor `stop`+`status:"error"` and `postToolUseFailure` classified; Codex failure path documented
- 6-tier spritesheet user model locked as canonical user segmentation

**Defers:**
- Gate badge UI (persistent visual indicator on the floating pet after animation TTL) — the renderer reads `gate.json` for animation precedence in Phase 07, but renders no badge widget yet
- Menubar badge count — needs real-world bubble interaction data post-Phase 06
- TDD gate states (`red_tdd`, `green_tdd`) and micro-gates (`open_pr`, `advance`, `record_review`) — defined and mapped; activate when SoA Phase 17 emits them
- Lite, SoA, RPG spritesheet art and row design — Phase 07 locks the enum contract; art delivery is per-sheet per phase
- VS Code / Antigravity adapters → Phase 09
- Premium SoA animation entitlement → Phase 14
- RPG spritesheet design → Phase 10+
- `work_mode` field — dropped entirely; `gate.json` + `activity_state` carry the information cleanly
- `gate_badge` field on `state.json` — dropped; the `gate.json` sidecar *is* the badge source

---

Phase 06 delivered the sticky gate interim fix, schema v3 (`standby`), Cursor v1 installer, attention bubble UI, and renderer TTL. Gate animations still flash and disappear because tool_use overwrites them after seconds — the root cause is the `events.ndjson` tail architecture, where gate events only render on the next hook call. Phase 07 makes the architecture change Phase 06 deferred: SoA writes a `gate.json` sidecar (son-of-anton Phase 17), the renderer reads it directly so gates show instantly and survive agent-idle windows, and the ActivityState enum is locked to the shape that supports 4-spritesheet expansion. This is the durable foundation for all future animation work.

## Phase Goal

This phase should leave the product in a state where:

- SoA gate animations (`ticket_started`, `adversarial_review`, `poll_review`, `review_clean`, `ticket_completed`) appear the instant SoA writes them and persist for their `expires_at` window during a live delivery session — not stomped within seconds, and visible even when no agent tool_use is firing (e.g., `ticket_completed` while you review the PR)
- After a gate's `expires_at` passes, the pet shows honest hook-driven animation (`implementing`, `testing`, `thinking`) while `gate.json` retains the gate context for a future badge UI
- `errored` fires on real API failures (Claude rate limit, Cursor error stop) within one hook invocation on a fixture payload — not only on synthetic `is_error`
- The 19-state closed ActivityState enum and 6-tier user model are locked in contracts — downstream phases use this as the stable animation foundation

## Committed Scope

### 1. `gate.json` sidecar consumer (renderer-owned)

son-of-anton Phase 17 (hard prerequisite) writes gate events to `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`) as `{ gate, since, expires_at }`. SoA owns this file exclusively.

- **Swift renderer reads `gate.json` directly** on its existing poll loop, merges with `state.json`, and resolves precedence: if `gate.json` is present and `gate.expires_at > now`, paint the SoA-sheet row for `gate.gate`; otherwise paint the hook-driven `state.json` `activity_state`.
- **Hook-binary drops all SoA awareness.** The `events.ndjson` tail reader is removed. The hook becomes a pure platform-event classifier (tool_use, Stop, StopFailure, etc.) writing only `state.json`. It never reads or writes `gate.json`.
- **No two-writer race:** SoA owns `gate.json`, hook owns `state.json`, renderer merges read-only. No shared-file write contention.
- **TTL-agnostic:** codogotchi honors `gate.expires_at` as written by SoA; it does not hardcode per-gate TTLs. (SoA Phase 17 ships a flat 3m v1 baseline; tuning is upstream.)
- **Forward-compat:** an unrecognized `gate` name in `gate.json` is ignored — the renderer falls through to `state.json` (hook-driven animation). No crash, no gray pet on version skew.
- **Absence handling:** missing or empty `gate.json` → pure hook-driven rendering.

### 2. Schema v4 — closed ActivityState enum

19-state closed enum replacing schema v3. Authoritative spec: [`notes/public/phase-06-animation-and-signal-research.md §8`](../../notes/public/phase-06-animation-and-signal-research.md). Breaking change; `schema_version` bump across contracts, hook-binary, Swift renderer, and fixtures.

**Hook + lite + Codex states (9):** `idle`, `standby`, `implementing`, `testing`, `thinking`, `reading`, `cramming`, `errored`, `waiting_for_input`

**SoA gate states (10):** `ticket_started`, `red_tdd`, `green_tdd`, `adversarial_review`, `open_pr`, `poll_review`, `record_review`, `advance`, `ticket_completed`, `review_clean`

**Deleted from enum (12):** `hyped`, `celebrating`, `calling_for_backup`, `waiting`, `focused`, `nervous`, `panicking`, `ascended`, `reviewing`, `pushing`, `running-tests`, `requesting_input`

Gate names in `gate.json` are exactly these schema-v4 SoA ActivityState values — the contract son-of-anton Phase 17 writes against.

### 3. Gate vocabulary aligned with ticket lifecycle

Updated gate → ActivityState mapping. Gates that depend on SoA Phase 17 emitting them are defined in the enum and mapped in the renderer; they activate when upstream lands. No Phase 07 exit condition gates on the unvalidated ones.

**Priority wiring — known-to-fire in real delivery data:**

| SoA gate (gate.json) | Lifecycle moment |
|---|---|
| `ticket_started` | Ticket begins / resumes (replaces `hyped`) |
| `adversarial_review` | Adversarial prompt write directed (replaces `calling_for_backup`; emit-then-action timing) |
| `poll_review` | AI review polling (replaces `waiting`) |
| `review_clean` | PR review clean (was part of `celebrating`) |
| `ticket_completed` | Ticket done on advance (was part of `celebrating`) |

`review_clean` and `ticket_completed` share the celebrating-row art for now (art split deferred).

**Retired (never fired in 6 days of real delivery):** `flow_state_entered` → `focused`, `risky_diff_detected` → `nervous`, `verification_failed` → `panicking`, `subagent_invoked` (misfire timing). ActivityStates deleted from the enum; gates not emitted.

**Wired but unvalidated (activate when SoA Phase 17 emits):** `red_tdd`, `green_tdd`, `open_pr`, `record_review`. `advance` is defined in the enum but son-of-anton Phase 17 does not emit it (deferred upstream — no hook in `closeout-stack.ts`).

### 4. Terminal failure hook parity

Register `StopFailure` in the Claude Code hook installer (alongside `PreToolUse`, `Stop`). Classify Cursor `stop`+`status:"error"` and `postToolUseFailure` (where `!is_interrupt`) as `errored`. Codex: document the discovery gap (no confirmed `StopFailure` equivalent in public docs); add a fixture or manual runbook step for Codex API failure. Exit condition is fixture-based for Claude and Cursor; real-world operator validation is the true signal for all platforms.

### 5. 6-tier spritesheet user model (locked)

Canonical user segmentation for all animation decisions going forward:

| Tier | Sheets | Notes |
|---|---|---|
| 1 | Codex-only | Minimum viable entry point |
| 2 | Codex + lite | Recommended base |
| 3 | Codex + SoA | Gate-only; coarser between-gate; lite recommended, not required |
| 4 | Codex + lite + SoA | Recommended SoA tier |
| 5 | Codex + lite + RPG | RPG requires lite |
| 6 | Codex + lite + SoA + RPG | Full stack |

**Installer rule:** SoA recommends lite but does not require it. RPG enforces lite as a prerequisite. Configurations without lite + RPG (Codex + RPG, Codex + SoA + RPG) are renderer-tolerant but unsupported — not tested or documented.

## Explicit Deferrals

- **Gate badge UI:** the renderer reads `gate.json` for animation precedence in Phase 07; the persistent floating-pet badge (rendering gate context after `expires_at`, positioning, dismiss) is a future phase once the UX is designed. `gate.json` already carries everything the badge needs.
- **Menubar badge count:** deferred until real-world interaction data accumulates post-Phase 06 attention bubble
- **TDD gates and micro-gates:** `red_tdd`, `green_tdd`, `open_pr`, `record_review` defined in enum, mapped in renderer, no exit condition — activate when SoA Phase 17 emits them. `advance` defined but not emitted upstream.
- **Lite, SoA, RPG spritesheet art:** Phase 07 locks enum contracts; per-sheet art delivery is independent of this phase
- **VS Code / Antigravity adapters:** Phase 09
- **Premium SoA animation entitlement:** Phase 14
- **RPG spritesheet design:** Phase 10+
- **`work_mode` field on `state.json`:** dropped; `gate.json` + `activity_state` carry the same information with a cleaner split
- **`gate_badge` field on `state.json`:** dropped; the `gate.json` sidecar is the gate-context source — a field on `state.json` would be redundant

## Exit Condition

Phase 07 is done when:

1. The hook-binary no longer reads `events.ndjson` and contains no SoA-event handling — it is a pure platform-event classifier writing only `state.json`.
2. The Swift renderer reads `gate.json` directly and merges with `state.json`: an unexpired gate paints its SoA-sheet row instantly (including during agent-idle windows with no tool_use); once `expires_at` passes, hook-driven animation shows through.
3. `adversarial_review` (via son-of-anton Phase 17's emit-then-action timing) appears at prompt-write direction time; the retired `subagent_invoked` path is gone from the codogotchi side.
4. An unrecognized `gate` name in `gate.json` is ignored and the renderer falls through to `state.json` — no crash, no gray pet.
5. On a fixture payload, Claude `StopFailure` and Cursor `stop`+`status:"error"` each produce `activity_state: "errored"` within one hook invocation and do not revert to `implementing` after subsequent heartbeats. Codex gap is documented.

## Dependencies

**son-of-anton Phase 17** (hard prerequisite — Phase 07 does not begin until Phase 17 is delivered): [`docs/product/plans/phase-17-codogotchi-direct-gate-write.md`](../../../son-of-anton/docs/product/plans/phase-17-codogotchi-direct-gate-write.md). SoA writes the `gate.json` sidecar (`{ gate, since, expires_at }`, flat 3m TTL v1) at 9 gate points with emit-then-action timing; `adversarial_review` fires before the adversarial-prompt write. Gate names match this plan's schema-v4 SoA ActivityState values.

**Phase 06** (delivered): sticky gate mechanic, schema v3, Cursor v1 installer, attention bubble + renderer TTL — all preconditions met.

## Retrospective

`required` — Phase 07 establishes the durable animation architecture (closed enum, 6-tier user model, `gate.json` sidecar, renderer-side merge) that all future animation phases build on. The sidecar's flat 3m TTL baseline is a deliberate starting guess; real delivery data post-Phase 07 will generate follow-up tuning and inform the deferred badge UI.
