# Codogotchi visibility granularity — v1 assumption, v2/v3 roadmap

Date: 2026-06-01

Status: **product stance + sequencing.** v1 ships the single-aggregate model. v2/v3 extend visibility when users run multiple agents or projects concurrently.

Related: [codogotchi-v2-per-platform-floating-pets.md](./codogotchi-v2-per-platform-floating-pets.md) (v2 implementation exploration).

## Core assumption (v1)

Codogotchi is built around **one active agent thread at a time** from the user's perspective:

- One `~/.codogotchi/state.json` snapshot (last hook write wins).
- One menubar pet and one attention bubble driven by that snapshot.
- One floating Maew for the aggregate “what is the agent doing right now?” signal.

That is a deliberate product choice, not an accident. Most sessions are “I'm in Cursor on this repo until I switch to Claude” — not five Composer tabs all waiting for input at once.

Hooks may fire from many threads and platforms; the **renderer** intentionally collapses them to a single visible state. Concurrent work still updates `state-transitions.log` for debugging; the pet shows the latest global signal.

## What still improves under v1 (session-keyed sidecar)

Features like **attention bubble prompt excerpts** (store prompt on `UserPromptSubmit` / `beforeSubmitPrompt`, consume on `stop` keyed by `session_id` / `conversation_id`) fit v1 well:

| Problem | Session-keyed sidecar |
| --- | --- |
| Wrong prompt text when a thread stops | Fixed — lookup by id on `stop` |
| Two threads waiting; show both bubbles | **Not fixed** — still one bubble |

The sidecar improves **accuracy of the one visible attention state**. It does not create a notification center for every waiting thread.

Keep `attention.reason_kind` as the enum (`input_requested`, `error_blocked`). Put human-readable excerpt text in `attention.summary` or a dedicated subtitle field; do not overload `reason_kind`.

## Evolution ladder

```text
v1 (now)     one state.json  →  one menubar pet + one floating pet
             assumption: one “foreground” thread matters

v2 (planned) platform-keyed state  →  optional floating pet per platform
             (Cursor / Codex / Claude Code), menubar stays aggregate

v3 (planned) project-keyed state   →  optional floating pet per project/repo root
             finer than platform when same IDE runs many workspaces
```

### v2 — floating pet per platform (user option)

**Goal:** User can see **up to three** concurrent agent surfaces (Cursor, Codex, Claude Code) without last-write-wins clobbering animation on the floating layer.

- **State model:** `state.json` becomes a **platform-keyed collection** (schema bump), not a single scalar. Each hook writes its platform slice.
- **UI:** Optional fan-out to ≤3 floating pets, each with a platform badge (top-left). Spatial layout so pets do not stack on the same pixel.
- **Menubar:** Stays **single aggregate** — shows the most recent transition across platforms; may switch which pet character/sheet is drawn when the latest event changes platform. Multiple menubar icons are explicitly out of scope.
- **Granularity:** Per **platform**, not per thread — bounded N, simpler lifecycle than per-session fan-out.

Detail: [codogotchi-v2-per-platform-floating-pets.md](./codogotchi-v2-per-platform-floating-pets.md).

### v3 — floating pet per project (user option)

**Goal:** When one platform (e.g. Cursor) runs agents in **multiple repos/worktrees**, visibility is per **project** (`repo_root` / `workspace_roots`), not only per IDE.

- **State model:** Extend keyed state with a **project** dimension (likely `source_event.repo_root` or normalized workspace root), still bounded compared to unbounded session ids.
- **UI:** Optional additional floating pets or layout rules per active project slice; exact UX TBD after v2 platform fan-out lands.
- **Open questions:** How many simultaneous project pets is sane; how SoA `gate.json` (global delivery) attaches to per-project pets; session end / TTL for despawn.

v3 depends on v2's keyed-state infrastructure — do not design project keys on top of today's scalar `state.json`.

## Menubar vs floating layer

| Surface | v1 | v2 | v3 |
| --- | --- | --- | --- |
| Menubar icon | Single aggregate | Single aggregate (latest transition) | Single aggregate |
| Floating pet(s) | One | Up to one per platform (opt-in) | Per-project option atop v2 |
| Attention bubble | One, tied to aggregate `state.json` | Likely per floating pet or still global — TBD in v2 design | TBD |

The menubar remains the **compact** “something happened” indicator. Floating pets carry **spatial** multi-agent awareness.

## Auto-generated thread titles

Sidebar titles (“Fun facts about bees”, etc.) are **not** available in hook stdin today. Prompt excerpts on standby (session-keyed sidecar) are the v1 substitute for “which thread needs me?” without waiting on IDE title APIs.

## Sequencing

1. **v1:** Session-keyed attention excerpts, native Cursor hooks, signal-honesty heuristics — all compatible with single visible pet.
2. **v2:** Platform-keyed `state.json` + optional multi-floating-pet (post–Lite+SoA v1 gate).
3. **v3:** Project-keyed slice + optional per-project floating pets after v2 proves keyed state and layout.

Do not block v1 attention work on multi-pet schema; do not slip v2 keyed state into the v1 release gate without an explicit phase and `schema_version` bump.

## One-line summary

**v1 = one visible agent moment; v2 = see each platform; v3 = see each project** — same hook pipeline, progressively richer keys in `state.json` and optional fan-out on the floating layer only.
