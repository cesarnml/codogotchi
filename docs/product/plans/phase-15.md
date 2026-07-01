# Phase 15: Per-Session Pets (Pet Per Active Agent Thread)

**Delivery status:** Product plan **approved 2026-07-01**. Target app **v2.2.0** (tentative). Next: `/soa decompose docs/product/plans/phase-15.md`.

## TL;DR

**Goal:** Render one pet panel per active agent session (`session_id`) on a platform — the render/lifecycle/UI half of "pet per active agent thread" — in Own and Minimalist modes, gated behind an opt-in per-platform setting.

**Ships:**

- **Per-session panels in Own and Minimalist modes** — one `FloatingPetPanel` / `MinimalistPanel` per active `session_id` on a platform, all rendering that platform's assigned (or Default) pet. Combined mode is untouched.
- **`PlatformSessionBadge`** — a per-session label ("Session 1", "Session 2", …) centered beneath the Platform + Animation badges on both Own panels and Minimalist strips, with a per-platform free-list numbering scheme, right-click **rename** (24-char limit, persisted in the session's `state.d` slice), and a delayed hover **tooltip** showing that thread's last submitted prompt.
- **Per-session lifecycle** — manual **"Prune Session"** right-click affordance, automatic TTL/idle-hibernation aging (Phase 14's mechanism keyed by `session_id`), a priority-ordered eviction queue when a cap is hit, and a rate-limited **conflict notification bubble** when every remaining panel is active.
- **Settings > "Platform Settings"** (renamed from "Platform Display Mode") — new **Enable Session Pets** checkbox (interactive only for Own/Minimalist) and **Session Cap** dropdown (`2–10` and `Unlimited`), one cap per platform shared across Own and Minimalist.
- **Off-by-default upgrade** — the v2 GitHub dmg ships every platform in Own mode with Enable Session Pets unchecked; upgrading is a visual no-op until the user opts in.

**Defers:**

- **Session-scoped pet identity ("pet collection per platform")** — distinct pets per session; deferred until a real user asks. No `assignments.json` `scope` field is added.
- **Session-linked SoA gate/ticket badges** — per-session SoA gate/animation attribution across codogotchi + upstream `cesarnml/son-of-anton`; explicit post-Phase-15 follow-up. SoA gate/badges continue to resolve per-platform this phase.
- **Combined-mode session-count signal** — considered and cut entirely (not parked).
- **True session-end detection** — TTL + manual prune is the accepted reaping contract; no new cross-platform "session ended" signal.

---

Phase 13 shipped one floating pet window per active platform; Phase 14 gave each platform its own pet *identity* and the chromeless Minimalist render path. Phase 14's retrospective named Phase 15 "pet per active agent thread" as the next step, and the post-Phase-14 mainline sweep already keys gate/badge routing by `origin:session_id`. This phase is the render/lifecycle/UI half: turn each active `session_id` into its own panel, with numbering, rename, aging, capacity, and the Settings surface to opt in.

## Phase Goal

This phase should leave the product in a state where:

- With Enable Session Pets **on** for a platform (Own or Minimalist), running three concurrent agent sessions on that platform shows **three panels**, each labeled "Session 1/2/3", all rendering that platform's pet.
- A user can **rename** a session panel (right-click → rename, ≤24 chars) and the label persists for that session's lifetime; hovering the animation badge after a short delay shows that thread's **last submitted prompt**.
- Session numbers are stable and **reused from a per-platform free-list** — a pruned/aged-out slot's number returns to the pool and the next new session takes the lowest free number (purely monotonic when the cap is Unlimited).
- A user can **manually prune** a session panel (right-click → Prune Session), which destroys the panel and deletes its `state.d` slice — the same end-state as automatic TTL expiry.
- When a platform is **at cap** and a new session arrives, an evictable panel is yielded in priority order (`idle`/`standby` → `errored` → `waiting_for_input`), and an **in-flight active** session is never auto-evicted.
- When **every remaining panel is active** and a new active session is blocked, a **dismissable bubble** appears on the longest-lived active session's panel; left-clicking it deep-links to **Settings > Customization**, and it is rate-limited to **one per platform per hour**. The blocked session is tracked in the background and promoted to a real panel the instant a slot frees.
- In **Settings > Platform Settings**, the columns read Platform, Mode, Enable Session Pets, Session Cap; the checkbox is interactive only for Own/Minimalist; enabling it exposes a cap dropdown defaulting to **3**.
- An upgrading v2 user sees **no change** until they opt in — every platform ships Own mode with session pets off.

## Committed Scope

### Render scope (Own + Minimalist only)

- One panel per active `session_id` on a platform, in **Own** and **Minimalist** modes.
- All session panels on a platform render the **same pet** — that platform's assigned pet, or the Default pet (no per-session identity this phase).
- **Combined mode is unchanged** — one shared window, no per-session multiplication, no session-count indicator.
- Toggling a platform between Own and Minimalist swaps `FloatingPetPanel`s for `MinimalistPanel`s for that platform's active sessions without resetting or splitting the cap.

### `PlatformSessionBadge` (identity & labeling)

- Horizontally centered beneath `PlatformChip` + `AnimationBadge` on Own panels and Minimalist strips; Minimalist's `AttentionBubble` anchor shifts down to make room.
- **Default label:** "Session N", counted per platform starting at 1.
- **Numbering:** monotonic while filling toward the cap; a freed number (pruned / TTL'd / idle-yielded) returns to a per-platform free-list and the next new session takes the **lowest free number**. Under an Unlimited cap there is no bounded pool, so numbering stays purely monotonic (no reuse). Reuse only happens after a slot is genuinely vacated — never taken from a live session.
- **Rename:** right-click → rename, **24-character limit**, persisted as `session_label` in that session's `state.d` slice (dies with the session file; no new top-level schema).
- **Tooltip:** hovering the animation badge shows a truncated version of the thread's last submitted user prompt after a short delay (exact delay left to implementation).

### Lifecycle, capacity, and eviction

- **Manual prune:** right-click → **"Prune Session"** destroys the panel and deletes its `state.d` slice.
- **Automatic aging:** reuse Phase 14's TTL / idle-hibernation mechanism (`dismissAttention` / `forceIdle`), keyed by `session_id`. TTL runs independently of cap pressure so dead panels don't linger forever.
- **Eviction priority when at cap** (most- → least-evictable), grounded against `ActivityState.swift`:
  1. `idle`, `standby`
  2. `errored`
  3. `waiting_for_input` (the live permission/approval gate — protected above idle/errored)
  4. Any in-flight active state (`implementing`/`editing`/`testing`/… + SoA gate-progress) — **never auto-evicted**.
- **All-remaining-active conflict:** do not evict an active session for a new one. Emit a **dismissable bubble** on the longest-lived active session's panel (the only surface with a render presence); left-click deep-links to **Settings > Customization**; **rate-limited to one bubble per platform per hour**. The blocked session's `state.d` slice is still written/tracked in the background and is promoted to a real panel the instant a slot frees.

### Settings > Platform Settings

- Section renamed "Platform Display Mode" → **"Platform Settings"**.
- Columns: **Platform, Mode, Enable Session Pets, Session Cap**.
- **Enable Session Pets** checkbox interactive only when Mode ∈ {Own, Minimalist}; disabled for Combined/Off.
- Checking it exposes the **Session Cap** dropdown: **`2–10` and `Unlimited`** (a cap of `1` is intentionally not offered). Default selection when first enabled: **3**.
- **One cap per platform**, shared across Own and Minimalist.

### Defaults & upgrade

- The official v2 GitHub dmg ships **every platform in Own mode with Enable Session Pets unchecked**. Upgrading from the prior version is a visual no-op until the user opts in per platform.

### SoA gate/animation (unchanged this phase)

- Existing **per-platform** SoA gate/ticket badge visualization stays as-is and is sufficient — only one SoA delivery runs at a time in practice. Session panels render; SoA gate/badges continue resolving per-platform.

## Explicit Deferrals

- **Session-scoped pet identity ("pet collection per platform")** — distinct pets drawn per session; deferred until a real user request surfaces it. No `assignments.json` `scope: persistent | session` field is added, because nothing consumes it yet.
- **Session-linked SoA gate/ticket badges** — per-session SoA gate/animation attribution requires coordinated changes across codogotchi and upstream `cesarnml/son-of-anton`; an explicit post-Phase-15 follow-up, shaped by this phase's retrospective. Not blocking, because there is only ever one SoA delivery running.
- **Combined-mode session-count signal** — rejected outright, not parked: it would leak per-session awareness into the one mode defined by opting out of that granularity, and a bare count isn't actionable there.
- **True session-end detection** — TTL + manual prune is the accepted reaping contract; a dead panel lingering until TTL is cosmetically harmless and the eviction priority queue already yields idle/standby sessions first under cap pressure. No new cross-platform end-of-session signal is built.

## Exit Condition

A developer can open Settings > Platform Settings, enable session pets for a platform in Own mode (cap defaulting to 3), run three concurrent agent sessions on that platform, and watch three pet panels appear labeled "Session 1/2/3", each rendering that platform's pet. Renaming a panel (≤24 chars) sticks for that session; hovering its animation badge surfaces the thread's last prompt. Pruning a session frees its number back to the pool, and the next new session reclaims the lowest free number. Pushing past the cap yields an idle/standby panel before an active one; when all three are actively working, a rate-limited bubble appears on the longest-lived panel and deep-links to Settings, and the blocked session pops in the moment one finishes. Flipping the platform to Minimalist swaps the pet panels for badge strips carrying the same per-session labels. A user who simply upgrades and never touches the new setting sees exactly what they saw before.

## Retrospective

`required` — Phase 15 introduces the first *session*-scoped lifecycle (free-list numbering, per-session rename persistence, the priority eviction queue, and the rate-limited conflict bubble) and deliberately leaves a named cross-repo follow-up (session-linked SoA gate attribution across codogotchi + upstream `son-of-anton`). Durable learning and downstream assumptions are likely, and the retrospective is where the post-Phase-15 extension work gets shaped.
