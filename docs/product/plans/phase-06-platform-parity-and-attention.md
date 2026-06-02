# Phase 06: Platform Parity and Attention UX

**Delivery status:** Delivered.

## TL;DR

**Goal:** Fix the two most visible gaps in lite-mode experience — the pet waves forever after a session ends, and SoA gate animations flash for seconds before being stomped by tool calls — and add Cursor as a first-class platform alongside honest Bash signal enrichment.

**Ships:**
- Rename `requesting_input` → `standby` across the full contract stack (contracts, hook, renderer, fixtures) — shipped in P6.01
- Attention bubble attached to the floating pet: short summary, ℹ️ info icon, hover-reveal `×` dismiss and contextual action button (`Focus` / `Reply`)
- TTL on `standby`: renderer shows `idle` once the attention payload expires, even if `state.json` still says `standby`
- Sticky gate mechanic: SoA gate states persist until the next gate fires or session ends — tool_use no longer stomps them
- 3-bucket Bash heuristic: `grep`/`find`/`cat`/`ls`/`tail` etc → `reviewing`; unknown Bash → `implementing` fallback; test runners already handled
- Cursor platform adapter v1: `Shell` parity with `Bash` classification, `afterFileEdit` → `implementing`, `source_origin: "cursor"` fix, native `~/.cursor/hooks.json` installer + bridge documentation
- Persist `tool.command` on `state.json` and transition log for Bash/Shell events

**Defers:**
- SoA writing directly to `~/.codogotchi/state.json` (replaces `events.ndjson` tail architecture) → Phase 07
- Full gate vocabulary redesign (`adversarial_prompt_written`, `verification_failed` trigger fix, `stage_advanced` wiring) → Phase 07
- Full `work_mode: thinking | implementing | testing` taxonomy and animation row remapping → Phase 07
- VS Code Copilot hook installer → Phase 09
- Menubar badge count (post-dismiss affordance) → Phase 07 (evaluate after bubble ships)
- `antigravity` without captured fixtures → Phase 09
- HUD hearts / XP → Phase 10+ (RPG-gated)

---

Codogotchi already has a richer animation vocabulary than the native Codex pet, but two problems erode trust: the pet waves indefinitely after every session end (no TTL), and SoA gate animations — the most expressive signals — are invisible in practice because tool_use events overwrite them within seconds. Phase 06 fixes both. It also closes the Cursor attribution gap (users getting Cursor-driven animations silently labeled `claude_code`) and enriches the Bash signal so the pet looks alive during the 48% of events that currently resolve to `idle`.

## Phase Goal

This phase should leave the product in a state where:

- A user who walks away mid-session returns to find the pet either showing a meaningful attention bubble or having decayed to `idle` — never frozen mid-wave indefinitely.
- SoA gate animations (`hyped`, `calling_for_backup`, `waiting`, `celebrating`) are visibly sustained for their natural gate-to-gate window (minutes, not seconds).
- A Cursor user's session correctly logs `source_origin: "cursor"` and shows `implementing`/`running-tests` from `Shell` commands, not `idle`.
- Bash-heavy sessions (grep/find/cat loops) show `reviewing` instead of a flat `idle` for the entire session.

## Committed Scope

### 1. Attention payload on `state.json`

Optional `attention` object written alongside `activity_state`:

- `reason_kind`: starter set — `input_requested`, `error_blocked`, `review_ready`
- `summary`: short human-readable string (populated by hook on `standby`-class states and `errored`)
- `created_at`: ISO timestamp
- `expires_at`: ISO timestamp

**Renderer TTL policy:** if `attention.expires_at < now`, renderer treats `activity_state` as `idle` regardless of what `state.json` says. Default TTL for `standby` is conservative (2h); `errored` is shorter (30m). Exact values are implementation decisions; the contract just requires `expires_at` to be present.

### 2. Attention bubble UI (floating pet)

Matches the Codex pet reference pattern:

- Bubble attached below the floating pet
- Shows `attention.summary` as primary text, `reason_kind` as subtitle
- ℹ️ icon (top-right): tappable, surfaces notification kind metadata
- **Hover state:** `×` dismiss inline on the left; contextual action button on the right
  - `input_requested` → `Focus` (best-effort bring IDE/agent app to foreground via `source_origin`)
  - `error_blocked` → `Reply` (focus the relevant session window)
- Dismiss clears the bubble; pet returns to `idle` pose
- Works in both lite and alive modes
- Bubble does **not** appear when the pet is collapsed to menubar-only

### 3. Sticky gate mechanic (hook)

SoA gate states (`hyped`, `calling_for_backup`, `waiting`, `celebrating`, etc.) persist in `state.json` until:

- A new gate event fires (next entry in `events.ndjson` tail), OR
- A `session_end` / `stop` event arrives (agent finished turn, awaiting input)

Tool_use events (`implementing`, `reviewing`, `running-tests`) do **not** clear a gate state during its window. No backward-compat shims — the tail reader stays, behavior just changes.

**Observed gate-to-gate windows from real delivery data:**
- `hyped` (ticket started → subagent invoked): median 8m, p90 2.8h
- `calling_for_backup` (subagent invoked → PR window opened): median 2.2m
- `waiting` (PR window opened → review clean): median 31s
- `celebrating` (review clean → next ticket started): median 16m, max 31h

### 4. Bash 3-bucket heuristic

Extends the existing `classifyEvent` in `hook-binary.ts`:

| Bash command pattern | State |
|---|---|
| `grep`, `find`, `rg`, `ls`, `cat`, `head`, `tail`, `wc`, `awk`, `sed`, `jq` | `reviewing` |
| `git push` | `pushing` (already works) |
| Test runners | `running-tests` (already works) |
| Anything else | `implementing` (replaces `idle` fallback) |

Cursor `Shell` tool is normalized to the same classification path as `Bash`. No separate branch.

### 5. Cursor platform adapter v1

Two tracks, kept distinct:

**Track A — Claude third-party bridge (already works):**
- Document in README/runbook: Cursor with Third-party skills enabled picks up `codogotchi-hook` from `~/.claude/settings.json` automatically
- Add optional `hooks install` check: detect bridge-vs-native and surface status in `codogotchi hooks status`

**Track B — Native Cursor hooks (new):**
- Installer writes `~/.cursor/hooks.json` calling `codogotchi-hook --platform cursor`
- `source_origin: "cursor"` emitted correctly (fix: `rawHookOrigin()` currently misattributes camelCase Cursor event names as `claude_code`)
- `afterFileEdit` hook event → `implementing` (Cursor's file-edit signal, not a `tool_use`)
- `workspace_roots[0]` used for SoA root resolution when `CURSOR_PROJECT_DIR` absent

### 6. Signal persistence

- `tool.command` (the raw Bash/Shell command string) written to `state.json` and appended to `state-transitions.log` for every Bash/Shell event
- Optional stub `work_mode` field in `state.json` contract (unpopulated; Phase 07 fills it)

## Explicit Deferrals

- **SoA direct write to `~/.codogotchi/state.json`:** the correct long-term architecture (eliminates `events.ndjson` tail hop, makes gate animations instant even when agent is idle). Deferred to Phase 07 because it requires SoA changes. No backward-compat bridge needed when it ships — single user.
- **Full gate vocabulary redesign:** `adversarial_prompt_written` timing fix (currently fires on subagent start, should fire on prompt write), `verification_failed` trigger hardening, `stage_advanced`/`ascended` wiring, `focused`/`nervous` trigger conditions. Phase 07.
- **`work_mode` taxonomy and animation row remapping:** `thinking | implementing | testing` as a renderer-visible field, plus deciding which codogotchi spritesheet rows to retire/repurpose for new semantics. Phase 07.
- **Menubar badge count:** post-dismiss count badge on the menubar icon. Evaluate after floating bubble ships and the interaction pattern is proven. Phase 07 candidate.
- **VS Code Copilot hook installer and tool alias table:** Phase 09.
- **Antigravity without captured fixtures:** Phase 09.
- **HUD hearts / XP:** Phase 10+ (RPG-gated).

## Exit Condition

Phase 06 is done when:

1. A manual test session ending with `standby` shows the bubble appear, then decay to `idle` after `expires_at` without any new agent event — "stuck waving" is gone.
2. A live SoA delivery session shows `hyped` and `celebrating` persisting for their natural gate-to-gate window, not flashing for seconds.
3. A Cursor session (native hooks or documented bridge) writes `source_origin: "cursor"` to `state-transitions.log` and shows `implementing` for file edits and `reviewing` for Shell reads — not `idle` or `claude_code`.
4. A Bash-heavy session (grep/find loops) shows `reviewing` in the transition log where it previously showed `idle`.
5. Runbook documents the bridge vs native install paths and when to prefer each.

## Retrospective

`skip` — no operator workflow change, no durable architectural boundary introduced. Phase 07 (SoA direct write) is the boundary worth reviewing after it lands.
