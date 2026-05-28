# Phase 06 Animation, Signal, and Spritesheet Research

_Session: 2026-05-28_
_Context: Phase 06 planning session — state-transitions.log analysis, animation vocabulary audit, spritesheet architecture decisions_

---

## 1. State-Transitions Log Analysis

**Source:** `~/.codogotchi.rpg-backup-20260528-141106/state-transitions.log`
**Period:** 2026-05-22 through 2026-05-28 (6 days of active delivery)
**Total transitions:** 1,805

### Per-state breakdown

| State | Count | % of all | Triggers | Median duration | Mode bucket | p90 | Max |
|---|---|---|---|---|---|---|---|
| `idle` | 876 | 48.5% | tool_use(820), unknown(31), session_end(12) | 30s | 10–30s | 4.1m | 10.7h |
| `implementing` | 384 | 21.3% | tool_use(381), unknown(3) | 7s | 2–10s | 39s | 33.9m |
| `requesting_input` | 285 | 15.8% | session_end(252), unknown(33) | 2.9m | 1–5m | 1.9h | 10.0h |
| `reviewing` | 135 | 7.5% | tool_use(135) | 10s | 2–10s | 52s | 9.6m |
| `hyped` | 35 | 1.9% | gate(35) | 5s | 2–10s | 19s | 19.1m |
| `celebrating` | 31 | 1.7% | gate(27), unknown(4) | 1.1m | 1–5m | 9.7m | 5.1h |
| `running-tests` | 23 | 1.3% | tool_use(21), unknown(2) | 5s | 2–10s | 16s | 6.5m |
| `waiting` | 19 | 1.1% | gate(19) | 12s | 10–30s | 17s | 21s |
| `calling_for_backup` | 15 | 0.8% | gate(15) | 7s | 2–10s | 23s | 41s |
| `pushing` | 2 | 0.1% | tool_use(2) | 22s | 10–30s | 22s | 22s |

**Never fired (0 occurrences in 6 days):** `focused`, `nervous`, `ascended`, `panicking`, `errored`

### Key findings

**`idle` is noise (48.5%):** Almost entirely from Bash/Shell commands falling through the classification gap. Every unknown Bash command → `idle`. The 3-bucket Bash heuristic (Phase 06) collapses most of this into `reviewing` and `implementing`.

**`requesting_input` semantic mismatch:** Fires after every `session_end` (agent completed a turn). It is NOT "agent urgently needs input" — it is "agent finished, ready for next prompt." Renamed to `standby` in Phase 06. Duration tail is the stuck-waving bug: median 2.9m is fine, but p90 = 1.9h and max = 10h.

**Gate animations are invisible:** `hyped` actual median = 5s, `calling_for_backup` = 7s. These flash and disappear because the next tool_use overwrites them. Gate-to-gate window (what they'd show if sticky) is 8.3m median for `hyped`, 2.2m for `calling_for_backup`.

**`celebrating` long tail is correct:** Median 16.2m, max 31h. The long tail = developer reviewing the PR before launching the next session. Desired behavior, not a bug.

**`waiting` is well-behaved:** Max 21s, always from SoA gate, always resolves fast. No TTL risk.

### Gate-to-gate durations (what gate animations would last if sticky)

| State | N | Median | p75 | p90 | Max |
|---|---|---|---|---|---|
| `hyped` | 35 | 8.3m | 20.7m | 2.8h | 13.1h |
| `celebrating` | 30 | 16.2m | 1.9h | 10.8h | 31.1h |
| `waiting` | 19 | 31s | 35s | 42s | 1.5m |
| `calling_for_backup` | 15 | 2.2m | 3.5m | 5.5m | 5.9m |

### Observed gate sequence (real delivery pattern)

```
ticket_started      → hyped           (8–20m median)
subagent_invoked    → calling_for_backup  (2–6m)
pr_review_window    → waiting         (~30s — AI review fires fast)
review_clean        → celebrating     (16m–hours)
[repeat per ticket]
```

`waiting` only lasts ~30s because `review_clean_recorded` fires right after the AI review completes. Semantically `waiting` = "AI review in progress" not "human reviewing PR."

---

## 2. Animation Vocabulary Audit

### Codex spritesheet (8 cols × 9 rows)

| Row | Codex label | Codogotchi `ActivityState` | Trigger |
|---|---|---|---|
| 0 | Idle | `idle` | No agent context |
| 1 | Run Right | _(interaction only)_ | Mouse drag |
| 2 | Run Left | _(interaction only)_ | Mouse drag |
| 3 | Wave | `standby` (was `requesting_input`) | session_end (agent turn done) |
| 4 | Jump | _(interaction only)_ | Mouse click |
| 5 | Failed | `errored` | is_error / max_tokens |
| 6 | Waiting | `waiting` | SoA pr_review_window_opened |
| 7 | Running | `implementing` | Edit / Write / MultiEdit |
| 8 | Review | `running-tests` | Bash test runner commands |

Note: Codex row 7 is labeled "Running" in the Codex spec but codogotchi uses it for `implementing` (seated with laptop). Maew's spritesheet was designed with this mapping in mind. Third-party Codex pets using the native sheet will show a running animation for `implementing` — semantic mismatch that the 2-sheet architecture resolves.

### Codogotchi spritesheet (24 cols × 9 rows — all 9 rows occupied)

| Row | `ActivityState` | SoA gate trigger | Fires in 6 days? |
|---|---|---|---|
| 0 | `celebrating` | ticket_completed, review_clean_recorded | ✓ 31x |
| 1 | `hyped` | ticket_started | ✓ 35x |
| 2 | `focused` | flow_state_entered | ✗ 0x |
| 3 | `nervous` | risky_diff_detected | ✗ 0x |
| 4 | `ascended` | stage_advanced | ✗ 0x |
| 5 | `calling_for_backup` | subagent_invoked | ✓ 15x |
| 6 | `panicking` | verification_failed | ✗ 0x |
| 7 | `reviewing` | Read × 3+ heuristic | ✓ 135x |
| 8 | `pushing` | Bash git push | ✓ 2x |

Rows 2, 3, 4, 6 are dead code in real delivery. Candidates for repurposing in the 2-sheet architecture (see section 3).

### Current Bash classification gaps

From `hook-binary.ts:classifyEvent()`:

| Tool / command | Current state | Better state |
|---|---|---|
| `Edit`, `Write`, `MultiEdit` | `implementing` | ✓ correct |
| `Bash` + `git push` | `pushing` | ✓ correct |
| `Bash` + test runner | `running-tests` | ✓ correct |
| `Bash` + `grep`/`find`/`ls`/`cat`/`tail`/`head`/`wc`/`rg` | `idle` | → `reviewing` |
| `Bash` + anything else | `idle` | → `implementing` (fallback) |
| `Shell` (Cursor) + any command | `idle` | → same 3-bucket as Bash |
| `Read` × 3+ | `reviewing` | ✓ correct |

---

## 3. Spritesheet Architecture Roadmap

### Design principle

Codex spritesheet compatibility is high priority. A user who imports their native Codex pet (`pet.json` + `spritesheet.webp`) gets a working pet immediately. Codogotchi reserves the right to use Codex animations with different trigger semantics to make the base vocabulary feel more alive (e.g., the `waving` row serves double duty as both the initial float-in greeting and the `standby` attention state when no codogotchi sheet is present).

### Four-tier spritesheet model

The guiding principle: **each sheet maps to a buy-in tier**. The renderer loads what exists; missing sheets fall back gracefully to the tier below. No sheet requires the one above it.

| Tier | File | Unlock condition | Animation vocabulary |
|---|---|---|---|
| 1 | `spritesheet.webp` | Import your Codex pet (Settings) | Codex vocabulary with codogotchi trigger semantics |
| 2 | `codogotchi-lite-spritesheet.webp` | Ships with default pets; published format | Enhanced non-SoA animations |
| 3 | `codogotchi-soa-spritesheet.webp` | SoA integration opt-in | SoA gate-triggered animations |
| 4 | `codogotchi-rpg-spritesheet.webp` | RPG alive mode (Convex enroll) | RPG milestone animations |

---

**Tier 1 — Codex sheet (BYO, always supported)**
- Any Codex-compatible `spritesheet.webp` + `pet.json` works via Settings → Import Pet
- Codogotchi maps its `ActivityState` vocabulary onto Codex rows using its own trigger semantics
- `waving` row: initial float-in greeting (one-shot) + `standby` fallback when no base sheet present
- `running` row: `implementing` fallback when no base sheet present

**Tier 2 — `codogotchi-lite-spritesheet.webp`**
Enhanced animation language — NOT linked to SoA usage:
- `thinking` (browsing/searching — grep/find/cat/ls)
- `implementing` (richer coding animation — distinct from Codex "running")
- `testing` (test/lint/format runners)
- `idle` progression: `idle` → `idle-impatient` (TTL ~5m) → `idle-frustrated` (TTL ~20m, pet is being ignored)
- Multiple `running-right` / `running-left` variants (selected at random on mouse drag)
- Multiple `jumping` variants (selected at random on click)
- Initial float-in greeting (one-shot on show floating pet)
- Optional: `waving-back` (hover interaction trigger)

**Tier 3 — `codogotchi-soa-spritesheet.webp`**
SoA gate-triggered animations — requires SoA integration:
- Current: `celebrating`, `hyped`, `calling_for_backup`, `waiting`, `reviewing`, `pushing`
- Phase 07 adds: updated gate vocabulary as triggers stabilize
- Zero-fire candidates for repurposing: `focused` (row 2), `nervous` (row 3), `ascended` (row 4), `panicking` (row 6)
- Users without SoA never load this sheet

**Tier 4 — `codogotchi-rpg-spritesheet.webp`**
RPG milestone animations — requires alive mode (Convex enroll):
- Level-up celebration (distinct from `celebrating` — more dramatic, earned milestone feel)
- Evolution milestone (pet transformation)
- Loot equip flash
- Health decay stage overlays or variants (thriving → getting sick → near death → ghost)
- XP milestone burst
- These should be the richest animations in the system — only users who've committed to the full RPG experience see them

### Why four sheets?

- Each sheet is independently purchasable/unlockable — monetization boundary is clean
- Size scales with commitment: lite users download Tier 1+2 only
- Prevents vocabulary bloat in any single sheet as all four expand independently
- A user who uses SoA but not RPG loads 1+2+3. A user who does RPG but not SoA loads 1+2+4. Fully additive.
- The renderer's loading logic is trivially: load each sheet if file exists, fall back to tier below for missing states

### Default pets at v1

Codogotchi ships 3 default pets (all spritesheets made by owner). v1 development continues with **Maew** only until v1 ships.

### Idle animation TTL design (sketch — not committed)

```
idle (default loop)
  → after ~5 min of no agent activity: idle-impatient
  → after ~20 min of no agent activity: idle-frustrated (long TTL, loops)
  → (future) hover during frustrated: one-shot tear animation
```

This makes the pet feel like it misses you without requiring any hook or agent event — purely renderer-side timer logic reading `state.json` timestamps.

---

## 4. Gate Vocabulary Redesign (Phase 07 scope)

### Current gate → state mapping problems

| Gate | Current state | Problem |
|---|---|---|
| `ticket_started` | `hyped` | ✓ correct, fires 35x |
| `subagent_invoked` | `calling_for_backup` | Fires too late — should be `adversarial_prompt_written` |
| `pr_review_window_opened` | `waiting` | ✓ correct, but only lasts ~30s |
| `ticket_completed` / `review_clean_recorded` | `celebrating` | ✓ correct |
| `verification_failed` | `panicking` | Never fires — trigger condition not met in normal delivery |
| `flow_state_entered` | `focused` | Never fires — condition unclear |
| `stage_advanced` | `ascended` | Never fires — not wired in current SoA |
| `risky_diff_detected` | `nervous` | Never fires |

### Proposed Phase 07 vocabulary

Replace `subagent_invoked` → `adversarial_prompt_written`: fire when the adversarial prompt is committed to the review artifact, not when the subagent process starts. Makes the animation honest (the intent is visible before the work begins).

Retire until wired: `flow_state_entered`, `risky_diff_detected` (evaluate whether these gates actually fire before assigning animations).

Harden: `verification_failed` trigger — confirm what conditions produce it and write a test.

---

## 5. Architecture Decision: SoA Direct Write

**Decision (Phase 06 planning, 2026-05-28):** SoA writes gate events directly to `~/.codogotchi/state.json`. The `events.ndjson` tail reader in `hook-binary.ts` is retired in Phase 07.

**Rationale:** The tail-pickup architecture means gate events are second-class citizens that only render on the next tool_use invocation. Real delivery shows `hyped` rendering for 5s (stomped) vs an 8.3m natural window. The indirection adds latency with no benefit — SoA already knows `~/.codogotchi/` via the hook binary it invokes. Direct write gives instant gate display and works during agent idle periods (e.g., `celebrating` persisting while the developer reviews a PR with no agent activity).

**Phase 06 interim:** sticky gate mechanic in `hook-binary.ts` — gate states persist until next gate or session_end. Tool_use doesn't clear them.

**Phase 07 full:** SoA writes `state.json` directly. Hook drops tail reader. Gate TTL (30s) prevents tool_use stomping a fresh gate during rapid post-gate agent activity.

**No backward-compat needed:** single user until v1.
