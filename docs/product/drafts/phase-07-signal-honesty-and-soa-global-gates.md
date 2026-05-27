# Phase 07 Draft — Signal Honesty and SoA Global Gates

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: [codogotchi-platform-extension-and-signal-pipeline-research.md](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md), [codogotchi-alignment-draft.md](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md)_

---

## Thesis

SoA delivery gates should reach Mali **even when hooks are quiet**, and the signal pipeline should be **debuggable and honest**: global gate log under `~/.codogotchi/`, richer transition metadata, and optional `work_mode` parallel to `activity_state`.

This phase is **infrastructure** for lite + alive users; it does not require RPG enrollment.

---

## The problem

- SoA writes only to **per-repo** `.soa/events.ndjson`; the hook only tails on the **next** hook invocation — missed gates during long quiet periods.
- Cursor/VS Code attribution and command strings incomplete (Phase 06 starts this; Phase 07 completes contract + SoA path). Until then, **Cursor Agent traffic often appears as `source_origin: claude_code`** because hooks run through Cursor’s **Claude third-party bridge** (`~/.claude/settings.json`) and `rawHookOrigin()` mis-classifies camelCase events — debugging “which IDE fired this?” from `state-transitions.log` alone is misleading ([platform research](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md)).
- Transition log cannot answer “what shell command caused this state?”

---

## Committed scope (Codogotchi repo)

### 1. Read `~/.codogotchi/gate-events.ndjson`

- Contract doc: line schema mirrors `.soa/events.ndjson` (or subset)
- Hook or menubar-side merge: **precedence** — fresh global gate → repo `.soa` tail → tool heuristics
- Tail semantics match existing inode/offset sidecar patterns

### 2. `work_mode` taxonomy (v1)

- Optional `work_mode: thinking | implementing | testing` on `state.json`
- `packages/cli/src/work-mode.ts` (or engine) with platform fixture tests
- Maps to existing `activity_state` defaults; does not replace SoA gate states

### 3. Transition log v2 fields

- `tool_command`, `work_mode`, `platform` on state change lines (`platform` must reflect **actual** agent surface: `cursor` vs `claude_code` vs `codex`, not bridge heuristic defaults)
- Backward compatible readers ignore unknown fields

### 4. Documentation

- Troubleshooting: `codogotchi.enabled`, global vs repo gate files
- Troubleshooting: **empty `~/.cursor/hooks.json` but pet still animates in Cursor** → third-party Claude hooks + `codogotchi-hook` in `~/.claude/settings.json`; how to read `Shell`/`Grep` vs `Bash` in logs
- Update `docs/contracts/soa-event-feed.md` producer/consumer boundary

---

## Committed scope (Son-of-Anton upstream)

_Deliver in `~/code/son-of-anton` as a separate plan/phase; codogotchi draft tracks dependency._

- `appendCodogotchiEvent()` → `~/.codogotchi/gate-events.ndjson` when `orchestrator.config.json` → `codogotchi.enabled !== false`
- Same gate names as Phase 15 repo writer (parallel write or shared helper)
- Document in SoA `AGENTS.md` / codogotchi alignment notes

**Suggested upstream slug:** `phase-17-codogotchi-global-gate-write` (number TBD in son-of-anton repo).

---

## Defers

- VS Code / Antigravity adapters → **Phase 14**
- Premium SoA animation entitlement → **Phase 13**

---

## Exit conditions

1. SoA `deliver` in a consumer repo appends a line visible in `~/.codogotchi/gate-events.ndjson`.
2. Hook classifies `hyped` from global file **without** a concurrent tool hook firing (test or runbook).
3. Transition log line includes `tool_command` for a Shell/Bash event.

---

## Dependencies

- **Phase 06** attention contract and Cursor origin (recommended first)
- **SoA upstream** global writer can land in parallel if contract is frozen first

---

## Next step

`/soa plan docs/product/drafts/phase-07-signal-honesty-and-soa-global-gates.md` (+ SoA upstream plan when scheduled)
