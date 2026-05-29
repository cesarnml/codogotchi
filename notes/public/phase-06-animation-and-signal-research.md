# Phase 06 Animation, Signal, and Spritesheet Research

_Session: 2026-05-28 (log analysis); 2026-05-29 (Tier 1 Codex-only mapping locked)_
_Context: Phase 06 planning session — state-transitions.log analysis, animation vocabulary audit, spritesheet architecture decisions. **§6** records agreed redesign for BYO `spritesheet.webp` users; lite / soa / rpg tiers are a separate follow-on.

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
| `standby` | 285 | 15.8% | session_end(252), unknown(33) | 2.9m | 1–5m | 1.9h | 10.0h |
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

**`standby` semantic mismatch:** Fires after every `session_end` (agent completed a turn). It is NOT "agent urgently needs input" — it is "agent finished, ready for next prompt." Renamed to `standby` in Phase 06. Duration tail is the stuck-waving bug: median 2.9m is fine, but p90 = 1.9h and max = 10h.

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
| 0 | Idle | `idle` | **Renderer fallback** (TTL decay — not hook-driven) |
| 1 | Run Right | _(interaction only)_ | Mouse drag |
| 2 | Run Left | _(interaction only)_ | Mouse drag |
| 3 | Wave | `standby` + greeting | Dual use — see below |
| 4 | Jump | _(interaction only)_ | Mouse hover |
| 5 | Failed | `errored` | Terminal turn failure — see below |
| 6 | Waiting | `waiting_for_input` | Platform blockers — see below |
| 7 | Running | `implementing`, `testing` | Active work — see below |
| 8 | Review | `thinking` | Bash explore bucket — see below |

**Authoritative Tier 1 spec:** §6. Rows 1–2 and 4 are `FloatingInteraction` only (never in `state.json`).

Note: On the BYO Codex sheet, row 7 is literally a **running** loop for both `implementing` and `testing` — a known visual compromise until **`codogotchi-lite-spritesheet.webp`** supplies typing/coding and proper test rows. Maew’s custom art already separates those on the lite sheet.

**Row 5 (`errored`) — agreed mapping, hook gap (2026-05-29):** Native Codex maps session `failed` → row 5 (`danger` notification). Codogotchi `ActivityState.errored` uses the same row. Meaning: the agent did not complete the turn successfully (rate limit, network, API error, truncation) — not “tool failed once while agent continues.” Classifier already handles `Stop` + `is_error` / `max_tokens` and generic `is_error`; **0 fires in 6 days** because the dominant failure path (Claude `StopFailure` on rate limit) never reaches the hook. Fix = register + classify the right terminal events per platform (no spritesheet change for BYO Codex pets):

| Platform | Hook that should clear `implementing` → `errored` |
|---|---|
| Claude Code | **`StopFailure`** (API errors; runs *instead of* `Stop`). Also `Stop` + `stop_reason: max_tokens`. Installer today: `PreToolUse` + `Stop` only. |
| Cursor (native) | **`stop`** with `status: "error"`; backstop **`postToolUseFailure`**, **`sessionEnd`** with `reason: "error"`. No `StopFailure` in Cursor docs. |
| Codex | **`Stop`** only in public docs — no `StopFailure`. Need a real fixture for API/rate-limit failures on `Stop` (`last_assistant_message`, etc.). |

Full hook research: `docs/product/drafts/phase-07-signal-honesty-and-soa-global-gates.md` § Platform hook research — failure → `errored`.

**Row 3 (`waving`) — agreed dual duty (2026-05-29):** Same Codex row, two triggers. Native Codex uses `waving` for **first-awake** when the floating pet appears (`first-awake` notification → row 3). Codogotchi **keeps** that greeting path: show floating pet → one-shot wave + “Hi” / short pet intro (renderer/UI; does not write `state.json`).

For users with **only** `spritesheet.webp` (no codogotchi extension sheets), row 3 **also** maps to **`standby`**: agent finished a turn successfully and is ready for the next prompt. Hook: **`Stop`** with no failure (`StopFailure` / `is_error` / `max_tokens` → `errored` instead). Meaning is *not* native Codex `waiting` (row 6 — approvals / blocked on user); it is “turn done, your move.” Phase 06 renames `requesting_input` → `standby` and adds attention TTL so wave does not stick for hours.

| Path | Mechanism | `ActivityState` | Codex row 3 |
|---|---|---|---|
| Show floating pet | Renderer one-shot greeting | _(none — overlay only)_ | Wave + intro copy |
| Agent turn ends OK | `Stop` hook (Claude/Codex); Cursor `stop` `status: "completed"` | `standby` | Wave (Codex-sheet-only users) |

When Tier 2+ sheets ship, `standby` may get a dedicated row on `codogotchi-lite-spritesheet.webp`; row 3 on the BYO Codex sheet remains greeting + Codex-only `standby` fallback.

**Row 6 (`waiting`) — rename + SoA split (2026-05-29):** Native Codex row 6 = user-input / approval / permission / MCP elicitation / plan blocked on human (`warning` notification). **`ActivityState` → `waiting_for_input`** (agreed; schema bump with `standby`). Rare in Yolo mode because those blockers are skipped — wire when we register platform hooks that surface them (`PermissionRequest`, etc.), not via SoA gates.

**Do not** use row 6 for SoA `pr_review_window_opened` (AI poll-review ~30s). That mapping was a convenience; semantics are wrong vs Codex. **Phase 07+:** `pr_review_window_opened` → dedicated SoA-only state (e.g. `poll_review` / `awaiting_ai_review`) on **`codogotchi-soa-spritesheet.webp`** only. Codex-sheet-only users never see it; BYO pets keep row 6 for true `waiting_for_input` only.

| State | Codex row 6? | Trigger |
|---|---|---|
| `waiting_for_input` | Yes (BYO sheet) | Platform: blocked on user (approval, permission, MCP, …) |
| _(SoA sheet TBD)_ | No — SoA extension row | `pr_review_window_opened` until `review_clean_recorded` |

Until SoA sheet lands, interim may keep gate→row 6 under old name `waiting` in code — migrate when splitting sheets.

**Row 0 (`idle`) — agreed (2026-05-29):** `idle` is the **floor state**, not a first-class hook target. Once attention / gate TTL lands, the renderer **resolves to `idle`** (Codex row 0) when nothing else applies. Hook may still *emit* `idle` as a classifier fallback today (Bash gaps, unknown gates) — that is misclassification noise, not “user entered idle.” Idle-impatient / idle-frustrated progression is **lite-sheet + renderer timers** (out of Tier 1 scope).

**Row 7 (`running`) — agreed (2026-05-29):** Codex row 7 maps to two hook-driven states on the BYO sheet only:

| `ActivityState` | Hook signal |
|---|---|
| `implementing` | `PreToolUse` — `Edit`, `Write`, `MultiEdit`; Bash fallback (non-test, non-explore) |
| `testing` | `PreToolUse` / `Bash` — test, lint, format runners (`bun test`, `pytest`, `vitest`, …) |

Both states paint **row 7** for Codex-only users. Closed enum: **`testing`** (replaces `running-tests`).

**Row 8 (`review`) — agreed (2026-05-29):** Codex row 8 is owned by **`thinking`** on Tier 1. Native Codex “output ready for your review” (`success` notification → mascot `review`) is **not targeted** — no reliable hook in Claude / Cursor / Codex public docs. If a hook appears later, row 8 may gain a second meaning; until then, do not fake it.

| `ActivityState` | Hook signal |
|---|---|
| `thinking` | `PreToolUse` / `Bash` / `Shell` — read-only explore: `grep`, `rg`, `find`, `ls`, `cat`, `tail`, `head`, `wc`, `awk`, … |

`reviewing` (Read ×3+), `pushing`, and all SoA gate states require **extension sheets** — Codex-only users do not get them on this sheet.

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
| `Bash` + `git push` | `pushing` | → extension sheet only (not Tier 1 Codex row) |
| `Bash` + test runner | `running-tests` (today) | → `testing` (Codex row 7; enum rename) |
| `Bash` + `grep`/`find`/`ls`/`cat`/`tail`/`head`/`wc`/`rg`/`awk` | `idle` | → `thinking` (Codex row 8) |
| `Bash` + anything else | `idle` | → `implementing` (Codex row 7) |
| `Shell` (Cursor) + any command | `idle` | → same 3-bucket as Bash |
| `Read` ×1–2 | `idle` (today) | → **`reading`** (lite row; Codex → row 8) |
| `Read` ×3+ | `reviewing` | → **`cramming`** (lite row; Codex → row 8) |

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
- Full row map: **§6 Conclusions — Tier 1 (Codex-only)**
- `waving` row: greeting (renderer) + `standby` (`Stop` success)
- `running` row: `implementing` + `testing` (both use row 7 — visual compromise)
- `review` row: `thinking` only; native Codex “output ready” review deferred
- `idle` row: renderer fallback after TTL — not hook-driven

**Tier 2 — `codogotchi-lite-spritesheet.webp`**
Enhanced animation language — NOT linked to SoA usage. Row map in progress: **§7**.

- Relieves Tier 1 double-duty rows (`standby`, `implementing`, `testing`, `thinking`, …).
- When lite sheet is present, Codex row 3 **`wave` is greeting / pet-hatch only** — not `standby`.
- `idle` progression: `idle` → `idle-impatient` (TTL ~5m) → `idle-frustrated` (TTL ~20m) — renderer timers (TBD in §7).
- Interaction polish: multiple run/jump variants, optional `waving-back` (TBD in §7).

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

### Idle animation TTL design (lite — locked in §7)

**Calm `idle` = Codex row 0.** **Impatient + frustrated rows live on the lite sheet only.** Renderer TTL; clock resets on any new `state.json` state transition. **v1: TTL only** — no interaction mood bump yet.

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

Replace `subagent_invoked` → `adversarial_review`: emit at the `write-subagent-adversarial-review` gate, **before** SoA directs the agent to begin writing the adversarial prompt ("emit then action") — not at subagent process start, and not after the prompt is committed. Emitting before the write extends the effective window and makes the animation honest (intent visible before work begins). **§8 is the authoritative emit spec; son-of-anton Phase 17 owns the emitter.**

Retire (never fired in real delivery): `flow_state_entered` → `focused`, `risky_diff_detected` → `nervous`. These gates are not emitted; their ActivityStates are deleted from the Phase 07 closed enum (see §8).

`verification_failed` → `panicking`: also retired from the Phase 07 enum (never fired). Terminal agent failure is covered by `errored` (Codex row 5) via platform failure hooks, not a SoA gate.

---

## 5. Architecture Decision: SoA Direct Write (sidecar)

**Decision (Phase 06 planning 2026-05-28; refined to sidecar in son-of-anton Phase 17 planning 2026-05-29):** SoA writes gate events directly to a dedicated sidecar `~/.codogotchi/gate.json` that SoA owns exclusively. The `events.ndjson` tail reader in `hook-binary.ts` is retired. The earlier "SoA writes `state.json` directly" framing is **superseded** — SoA and the hook-binary must never share a writer on the same file.

**Rationale:** The tail-pickup architecture means gate events are second-class citizens that only render on the next tool_use invocation. Real delivery shows `hyped` rendering for 5s (stomped) vs an 8.3m natural window. The indirection adds latency with no benefit. A **sidecar** (`gate.json` owned by SoA, `state.json` owned by the hook) eliminates the two-writer race entirely: no read-modify-write merge, no concurrent-write corruption window. The renderer reads both and merges on poll.

**Phase 06 interim:** sticky gate mechanic in `hook-binary.ts` — gate states persist until next gate or session_end. Tool_use doesn't clear them.

**Phase 07 + son-of-anton Phase 17 full:** SoA writes `gate.json` (sidecar). Path: `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`). Hook drops tail reader and never touches `gate.json`. Each gate write carries `{ gate, since, expires_at }`. **Authoritative spec for the writer and gate TTLs: [son-of-anton Phase 17 plan](../../../son-of-anton/docs/product/plans/phase-17-codogotchi-direct-gate-write.md).**

**No backward-compat needed:** single user until v1.

---

## 6. Conclusions — Tier 1 (Codex-only `spritesheet.webp`)

_Locked: 2026-05-29._ Applies to users who import **`pet.json` + `spritesheet.webp`** only (no `codogotchi-*-spritesheet.webp`). Extension buy-ins (**lite**, **soa**, **rpg**) are documented separately when that tier is designed.

### Scope

- **In:** 8×9 Codex grid rows 0–8, `ActivityState` strings written by the hook (where applicable), `FloatingInteraction` for rows 1/2/4, renderer policy for `idle` and greeting.
- **Out:** SoA gates, `reviewing` (Read×3), `pushing`, RPG overlays, lite idle progression, dedicated typing/test art — require extension sheets.

### Master map

| Row | Codex label | `ActivityState` / overlay | Driver | Status |
|:---:|---|---|---|---|
| 0 | Idle | `idle` | Renderer fallback after TTL / no signal | Agreed |
| 1 | Run right | `FloatingInteraction.runningRight` | Horizontal drag Δx > 0 | Agreed — no change |
| 2 | Run left | `FloatingInteraction.runningLeft` | Horizontal drag Δx < 0 | Agreed — no change |
| 3 | Wave | _(none)_ + `standby` | Greeting: show floating pet; standby: `Stop` success | Agreed |
| 4 | Jump | `FloatingInteraction.jumping` | Mouse hover (not click) | Agreed — no change |
| 5 | Failed | `errored` | `StopFailure`, `Stop`+failure, Cursor error stops | Agreed — hooks TBD |
| 6 | Waiting | `waiting_for_input` | `PermissionRequest` (Claude/Codex); Cursor `before*Execution` best-effort | Agreed — hooks TBD |
| 7 | Running | `implementing`, `testing` | Edit/Write; test runners; Bash fallback | Agreed |
| 8 | Review | `thinking` | Bash/Shell explore bucket | Agreed; native review **deferred** |

### Hook buckets (Tier 1 agent activity)

```
Edit / Write / MultiEdit     → implementing  → row 7
Bash test/lint/format        → testing       → row 7
Bash grep/rg/find/ls/cat/…   → thinking      → row 8
Stop (success)               → standby       → row 3
StopFailure / error          → errored       → row 5
PermissionRequest            → waiting_for_input → row 6
(no signal / TTL expired)    → idle          → row 0  (renderer)
```

### Enum / schema notes (implementation backlog)

| Decision | Action |
|---|---|
| `requesting_input` → `standby` | Schema v3 + attention TTL (Phase 06) |
| `waiting` → `waiting_for_input` | Same bump; stop mapping SoA `pr_review_window_opened` to row 6 |
| `running-tests` → `testing` | **Required** enum rename (`ACTIVITY_STATES`, Swift, contracts, fixtures) — same schema bump as `standby` / `waiting_for_input` |
| `thinking` | Add to closed enum + hook 3-bucket (explore → `thinking`) |
| SoA `pr_review_window_opened` | Future **soa** sheet only (e.g. `poll_review`) |

### Platform hooks to register (Tier 1 parity)

| Platform | Beyond today’s `PreToolUse` + `Stop` |
|---|---|
| Claude Code | `StopFailure`, `PermissionRequest` (+ optional `Notification` / `Elicitation`) |
| Codex | `PermissionRequest` (on existing Codex hook set) |
| Cursor | `beforeShellExecution`, `beforeMCPExecution`, `stop` with `status`, clear on `after*` |

### Known compromises (accepted for Tier 1)

1. Row 7 **running** art during coding and tests — fixed by **lite** sheet.
2. Row 3 **wave** doubles as greeting + `standby` — fixed by **lite** `standby` row when sheet present.
3. Row 8 native Codex **review** notification not replicated — row 8 used for **`thinking`** only.
4. Read×3+ **`reviewing`** invisible on Tier 1 — needs **soa** or **lite** row.

### Next tier

See **§7** (lite sheet — in progress).

---

## 7. Conclusions — Tier 2 (`codogotchi-lite-spritesheet.webp`)

_In progress: 2026-05-29._ Users with a **spec-compliant** `codogotchi-lite-spritesheet.webp` (BYO or premium art derived from their Codex sheet) load **Tier 1 + Tier 2**. Renderer resolves `ActivityState` on the lite sheet first, then falls back to Tier 1 Codex rows only for states the lite sheet does not define.

### Sheet format (stub)

- Grid and `pet.json` companion fields TBD (likely 24×9 to match Maew; publish a lite spritesheet contract doc when the first row map stabilizes).
- Buy-in levels above Codex: **lite**, **soa**, **rpg** (three extension sheets).

### Vocabulary table (building)

Columns: **Animation label** (artist-facing), **`ActivityState`**, **Trigger**, **hasTTL**.

| Animation label | `ActivityState` | Trigger | hasTTL |
|---|---|---|---|
| standby | `standby` | Agent turn completed successfully — **`Stop`** (Claude/Codex) or analogous (**Cursor** `stop` with `status: "completed"`). Not `StopFailure` / not `errored`. | **Yes** |
| implementing | `implementing` | **`PreToolUse`** — `Edit`, `Write`, `MultiEdit`. **`Bash` / `Shell`** when the command indicates a **write** action (mutating shell: e.g. redirects to file, `sed -i`, `tee`, `cp`/`mv`, `install`, patch apply — not read-only explore, not test runners). | **No** |
| testing | `testing` | **`Bash` / `Shell`** when the command is a **test runner**, **linter**, **formatter**, or **static-analysis** tool (e.g. `bun test`, `pytest`, `vitest`, `eslint`, `prettier`, `tsc --noEmit`, `cargo clippy` — classifier prefix list TBD). | **No** |
| thinking | `thinking` | **`Bash` / `Shell`** — **read + search** commands (e.g. `grep`, `rg`, `find`, `ls`, `cat`, `tail`, `head`, `wc`, `awk`, `git log`, `git diff`, … — classifier list TBD). | **No** |
| reading | `reading` | **`PreToolUse` `Read`** ×1–2 (streak; reset on write tools). Lite row; **Codex fallback: row 8 `review`**. | **No** |
| cramming | `cramming` | Same streak, **`Read` ×3+**. Lite row; **Codex fallback: row 8 `review`**. | **No** |
| idle | `idle` | **Codex sheet row 0** — base idle loop (Tier 1). Lite sheet does **not** ship a separate calm-idle row. | **30m** → impatient |
| idle-impatient | `idle` | **Lite sheet only** — renderer after 30m on idle floor. | **60m** → frustrated |
| idle-frustrated | `idle` | **Lite sheet only** — renderer 60m after impatient (90m from landing on idle). | loops until transition |
| errored | `errored` | **Codex row 5** always — lite sheet has **no** failed row. | No (hook clears on next event; `errored` attention ~30m per Phase 06) |
| waiting_for_input | `waiting_for_input` | **Codex row 6** always — lite sheet has **no** waiting row. | No |

#### `standby` (locked)

- **Meaning:** Task/turn finished; agent is ready for the next prompt (“your move”). Same hook signal as Tier 1, but **lite sheet owns the pixels** — ends the Codex **wave** double-duty.
- **Tier 1 fallback (no lite sheet):** `standby` still maps to Codex row 3 (wave).
- **Tier 2 (lite present):** dedicated **standby** row on `codogotchi-lite-spritesheet.webp`. Codex row 3 **wave** = **greeting / pet hatch only** (renderer one-shot on show floating pet — not written to `state.json`).
- **TTL:** Hook writes `attention` with `expires_at` (Phase 06: **2h** for `reason_kind: "input_requested"`). Renderer treats expired attention as **`idle`** (row 0) without a new hook event — fixes stuck wave.
- **UI:** Attention bubble while unexpired (Phase 06 `input_requested` → “Waiting for your input”).

#### `implementing` (locked)

- **Meaning:** Agent is **mutating** the codebase (typing/editing/writing files) — Maew-at-keyboard art, not Codex row 7 “running.”
- **Tier 1 fallback (no lite sheet):** `implementing` paints Codex row 7 (running loop) — visual compromise.
- **Tier 2 (lite present):** dedicated **implementing** row on `codogotchi-lite-spritesheet.webp`. Ends sharing row 7 with `testing`.
- **Trigger:** Hook classifies on **`PreToolUse`** write tools plus **`Bash` / `Shell`** when the command is a write/mutate pattern (Phase 06+ 3-bucket: write bucket → `implementing`; explore → `thinking`; runners → `testing`). Exact Bash allowlist TBD in classifier.
- **TTL:** **No** — cleared by the next hook event (tool_use, `Stop`, gate, etc.).

#### `testing` (locked)

- **Meaning:** Agent is running **verification** — tests, lint, format, static analysis — not editing and not read-only explore.
- **Tier 1 fallback (no lite sheet):** `testing` paints Codex row 7 — shares the **running** loop with `implementing`.
- **Tier 2 (lite present):** dedicated **testing** row on `codogotchi-lite-spritesheet.webp`. Row 7 on the Codex sheet is no longer used for tests when lite is loaded.
- **Trigger:** **`Bash` / `Shell`** only — match test/lint/format/static-analysis commands (same family as today’s `TEST_RUNNER_PREFIXES` in `hook-binary.ts`, extended for linters/formatters).
- **TTL:** **No**.

#### `thinking` (locked)

- **Meaning:** Agent is **exploring** via shell — grep/find/cat, not mutating, not running verification.
- **Tier 1 fallback (no lite sheet):** `thinking` paints Codex row 8 (**review** row). Native Codex “output ready for review” is **not** hooked — row 8 is explore-only on Tier 1.
- **Tier 2 (lite present):** dedicated **thinking** row on `codogotchi-lite-spritesheet.webp`. Ends overloading Codex row 8.
- **Trigger:** **`Bash` / `Shell`** read/search bucket only (not `Read` tool — see **`cramming`**).
- **TTL:** **No**.

#### `reading` / `cramming` (locked)

Two **lite** rows for the agent **`Read`** tool — same persisted `read_run` counter, reset on `Edit` / `Write` / `MultiEdit`:

| `read_run` | `ActivityState` | Vibe |
|:---:|:---:|---|
| 1–2 | **`reading`** | Flipping through files — light read |
| 3+ | **`cramming`** | Deep study before writing (old `reviewing` ×3 signal) |

- **`thinking`** stays **Bash/Shell only** — not used for `Read`.
- **Tier 1 (Codex only):** both **`reading`** and **`cramming`** paint **Codex row 8 (`review`)** — same art, two enum states; best match for agent `Read` without a lite sheet.
- **Tier 2 (lite):** separate **`reading`** and **`cramming`** rows on `codogotchi-lite-spritesheet.webp` (no longer overload row 8 for lite users).
- **TTL:** **No** for both.
- **Telemetry:** ×3+ bucket was **135×** as `reviewing`; ×1–2 were invisible in **`idle`** — `reading` fixes that.

#### `idle` / `idle-impatient` / `idle-frustrated` (locked)

- **`ActivityState` in `state.json`:** stays **`idle`** for all three animation labels. Enum does not multiply for mood (keeps hook single-writer simple).
- **Sheet split (lite users load Codex + lite):**
  - **`idle` (calm)** → pixels from **`spritesheet.webp` row 0** (Codex base). Lite sheet has **no** calm-idle row.
  - **`idle-impatient`** → pixels from **`codogotchi-lite-spritesheet.webp`** only.
  - **`idle-frustrated`** → pixels from **`codogotchi-lite-spritesheet.webp`** only.
- **Codex-only users (no lite sheet):** row 0 `idle` only — never see impatient/frustrated.
- **Not hook-driven:** impatient/frustrated are **never** written to `state.json`.
- **Clock:** Time since **last state transition**. New agent activity → back to **Codex calm idle** (fresh 30m timer).
- **Degradation ladder — Option A (locked):** 30m → lite impatient → +60m → lite frustrated (90m from landing on idle). Not Option B (60m frustrated from first idle).

| Animation label | Sheet | Enter |
|---|---|---|
| idle | **Codex** row 0 | Floor / decay / hook `idle` |
| idle-impatient | **Lite** | 30m no transition on idle floor |
| idle-frustrated | **Lite** | 60m after impatient |

- **Future (out of v1):** pet interaction bumps mood back toward calm Codex idle — TTL-only for now.

#### `errored` / `waiting_for_input` (locked — Codex pixels only)

- **Codex + lite users:** reuse **Tier 1 Codex rows** for these states. No lite-sheet rows — same hooks/triggers as §6; only pixel source is Codex `spritesheet.webp`.
- **`errored`:** row 5 — `StopFailure`, failed `Stop`, Cursor error stops (hooks TBD).
- **`waiting_for_input`:** row 6 — `PermissionRequest` (and peers); rare in Yolo mode.

### Tier 1 vs Tier 2 — `standby` / wave

| User has | `standby` animation | Codex row 3 `wave` |
|---|---|---|
| Codex sheet only | wave (double duty) | greeting + standby |
| Codex + lite sheet | lite **standby** row | greeting / hatch only |

### Tier 1 vs Tier 2 — `implementing` / running row

| User has | `implementing` animation | Codex row 7 `running` |
|---|---|---|
| Codex sheet only | row 7 (running) | also used for `testing` |
| Codex + lite sheet | lite **implementing** row | lite **testing** row (row 7 unused for agent states) |

### Tier 1 vs Tier 2 — `thinking` / `reading` / `cramming` / review row

| User has | `thinking` | `reading` / `cramming` | Codex row 8 `review` |
|---|---|---|---|
| Codex sheet only | row 8 (Bash explore only) | **row 8** for both `reading` & `cramming` (`Read` tool) | agent file reads |
| Codex + lite sheet | lite **thinking** | lite **reading** + **cramming** rows | unused for agent states |

### Next lite rows

_To document in this table:_ interaction variants (hatch, run/jump variants, `waving-back`).

---

## 8. Conclusions — Tier 3 (`codogotchi-soa-spritesheet.webp`) — in progress

_Locked: 2026-05-29 (vocabulary draft); TTL + write model aligned to son-of-anton Phase 17._ Requires **SoA sheet** loaded. SoA writes the **`gate.json` sidecar** (not `state.json` — see §5).

**Out of scope for SoA pet animations:** `/soa plan`, `/soa decompose`, `/soa closeout` — no gates, no sprites. During those phases the pet uses **normal hook heuristics** (`implementing`, `thinking`, `testing`, `standby`, …) like any other agent session.

**In scope:** `bun run deliver …` ticket gates only. **Sticky gate, short TTL, then hooks bleed through.** A gate wins over hook `tool_use` for its TTL window — so `ticket_started` is not erased by Bash in 5s. But the TTL is deliberately **short** so that after the gate has had its visible moment, hook-driven agent-activity animations (`implementing`, `testing`, `thinking`) **bleed through** rather than being fully suppressed by a long gate TTL. The gate context is not lost — it persists on the `gate.json` sidecar (badge layer) until the next gate fires.

**TTL policy (revised):** All gates ship at a **flat 3m TTL** as the v1 baseline (set in son-of-anton Phase 17). This is intentionally short to explore the bleed-through balance — gate gets its moment, then real work shows through. Tune individual gates up/down from `state-transitions.log` after a few real delivery runs. **son-of-anton Phase 17 is authoritative for emitted TTLs.**

### Vocabulary table (draft)

Emit model is **"emit then action"** — SoA writes the gate *before* directing the agent to the action, extending the effective window. TTLs are flat 3m v1 (see son-of-anton Phase 17). `advance` is defined in the enum but **not emitted in Phase 17** (deferred — no hook in `closeout-stack.ts`).

| Animation label | `ActivityState` | Gate (emit trigger — emit then action) | TTL (v1) |
|---|---|---|---|
| ticket_started | `ticket_started` | Before agent begins ticket work: `start`; `advance` auto-start (cook mode); `resume` on an `in_progress` ticket | 3m |
| red_tdd | `red_tdd` | Before directing agent to write failing tests (TDD red instruction) | 3m |
| green_tdd | `green_tdd` | When `post-red` records (failing tests confirmed), before directing agent to implement; **closes on next gate fire** (`adversarial_review` / `open_pr`), not on `post-verify` | 3m |
| adversarial_review | `adversarial_review` | Before directing agent to write the adversarial prompt: **`write-subagent-adversarial-review`** (not `subagent-review`, not runner start) | 3m |
| open_pr | `open_pr` | Before `gh pr create` (`open-pr`) | 3m |
| poll_review | `poll_review` | Before directing agent to poll review | 3m |
| record_review | `record_review` | Before `record-review` records outcome | 3m |
| advance _(deferred)_ | `advance` | `advance` beat between tickets — **defined in enum, not emitted in Phase 17** | 3m |
| ticket_completed | `ticket_completed` | Ticket → `done` on `advance` | 3m |
| review_clean | `review_clean` | PR review outcome **clean** — across `record-review` / `poll-review` / `triage-ticket` | 3m |

### Precedence (renderer reads two files: `gate.json` sidecar + `state.json`)

```
read gate.json (SoA-owned) and state.json (hook-owned)
if gate.json present and gate.expires_at > now:
  ANIMATION: paint SoA sheet row for gate.activity_state
else:
  ANIMATION: hook classifies state.json activity_state
             → implementing | thinking | testing | … (lite sheet first, Codex fallback)
BADGE (future UI): if gate.json present, show gate context regardless of expires_at
                   (cleared only when SoA overwrites gate.json on next gate or resolution)
```

**No special-case suppression during `green_tdd`.** The old "stay on green_tdd until post-verify" model is **retired** — that long suppression is exactly what the short TTL is replacing. `green_tdd` shows for its 3m TTL, then hook-driven animations (`implementing`, `testing`) bleed through to reflect the real work, while the `gate.json` sidecar keeps `green_tdd` as the badge context until the next gate fires.

### Retired / renamed (from old codogotchi mapping)

| Old | New |
|---|---|
| `waiting` ← `pr_review_window_opened` | **`poll_review`** (SoA sheet) |
| `hyped` ← `ticket_started` | **`ticket_started`** (one row — drop `hyped` label unless art keeps the name) |
| `celebrating` ← both clean + completed | Split **`review_clean`** + **`ticket_completed`** (or one row TBD) |
| `calling_for_backup` ← `subagent_invoked` | **`adversarial_review`** at write time |
| `subagent_invoked` NDJSON | Retire for pet timing; optional telemetry only |

**Not animated on SoA sheet:** `planning`, `decomposing`, `closeout`. **Contract-only, not wired:** `flow_state_entered`, `risky_diff_detected`, `stage_advanced`, `verification_failed`.

### Implementation notes

1. SoA writes the **`gate.json` sidecar** (`{ gate, since, expires_at }` per gate). SoA owns this file exclusively; the hook never writes it. (son-of-anton Phase 17.)
2. Hook binary: writes `state.json` only; **never reads or writes `gate.json`**. The renderer (not the hook) merges the two files and resolves precedence by `expires_at`.
3. Emit **`adversarial_review`** on `write-subagent-adversarial-review`, not runner start; "emit then action" for all gates.
4. All gates ship at **flat 3m TTL** (v1). Revisit per-gate after real delivery — the goal is gate-gets-its-moment-then-hooks-bleed-through, not long suppression.

### Closed `ActivityState` enum — Phase 07 schema bump (locked 2026-05-29)

**19 states total.** Renames are breaking (`schema_version` bump). RPG sheet may reintroduce milestone labels later (**not** in this enum).

#### Hook + lite + Codex (9)

| `ActivityState` | Sheet / driver |
|---|---|
| `idle` | Codex row 0 + lite impatient/frustrated (renderer phases) |
| `standby` | Lite (`Stop` success); Codex wave = greeting only |
| `implementing` | Lite |
| `testing` | Lite (replaces `running-tests`) |
| `thinking` | Lite — Bash explore; Codex row 8 fallback |
| `reading` | Lite — `Read` ×1–2; Codex row 8 (`review`) fallback |
| `cramming` | Lite — `Read` ×3+; Codex row 8 (`review`) fallback |
| `errored` | Codex row 5 |
| `waiting_for_input` | Codex row 6 (platform `PermissionRequest`; **not** `poll_review`) |

#### SoA delivery gates (10) — `codogotchi-soa-spritesheet.webp`

| `ActivityState` | Replaces (deleted) |
|---|---|
| `ticket_started` | `hyped` |
| `red_tdd` | _(new)_ |
| `green_tdd` | _(new)_ |
| `adversarial_review` | `calling_for_backup` |
| `open_pr` | _(new; was NDJSON only as `pr_review_window_opened`)_ |
| `poll_review` | `waiting` (SoA AI-review window) |
| `record_review` | _(new)_ |
| `advance` | _(new)_ |
| `ticket_completed` | `celebrating` (partial — ticket done) |
| `review_clean` | `celebrating` (partial — PR clean) |

#### Deleted from enum (Phase 07)

| Removed | Notes |
|---|---|
| `hyped` | → `ticket_started` |
| `celebrating` | → `review_clean` + `ticket_completed` |
| `calling_for_backup` | → `adversarial_review` |
| `waiting` | → `poll_review` (SoA); platform wait = `waiting_for_input` |
| `focused`, `nervous`, `panicking` | Retired; never fired |
| `ascended` | Retired from Phase 07 enum; see RPG deferral |
| `reviewing` | → **`reading`** (×1–2) + **`cramming`** (×3+) |
| `pushing` | No SoA row; hook heuristic dropped for now |
| `running-tests` | → `testing` |
| `requesting_input` | → `standby` |

#### Deferred — RPG sheet only (out of Phase 07 scope)

May return as **separate** `ActivityState` values or RPG-only presentation when `codogotchi-rpg-spritesheet.webp` is designed — **not** in the Phase 07 closed enum:

- **`celebrating`** (milestone / victory — richer than `review_clean`)
- **`ascended`** (stage / evolution)

Phase 07 implementation uses this doc + §6 (Codex-only) + §7 (lite) + §8 (SoA); code changes (`animation-state.ts`, `SOA_EVENT_TO_ACTIVITY_STATE`, Swift `ActivityState`, hook maps) follow in a dedicated schema-bump ticket.
