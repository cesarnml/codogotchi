# Codogotchi v2 — per-platform floating pets

Date: 2026-05-31

Status: **idea / exploration — explicitly post-v1, targeted at v2.** Not for the current Lite+SoA v1 release gate (Phase 08). Captured here so the design is not lost.

## The idea

Today Codogotchi renders **one** floating pet for the aggregate "what is the agent doing right now" signal. v2 explores spawning **one floating pet per active agent platform** (Claude Code, Codex, Cursor) so you can see all your running agents at a glance instead of one clobbered aggregate.

**Granularity decision: per active agent _platform_, not per thread.** This is deliberate — see the granularity tradeoff below. Per-thread is a possible *later* evolution of the same keyed-state model, not part of this artifact.

Definition of **"active"**: the agent _application is running_, not necessarily processing a task. An idle-but-running platform shows its pet in the default `idle` state. So "active" is "we've seen this platform's hooks alive" — the existing `idle` default already covers the not-currently-working case; no new "asleep" concept needed.

## Why this granularity (the crux)

`state.json` today is a **single scalar aggregate** — there is zero `session_id`/thread/platform key anywhere in `packages/contracts` or `hook-binary.ts`. The whole contract is one `ActivityState` → one pet. The real work of "multiple pets" is **giving `state.json` a key**, turning the scalar into a keyed collection. Everything else follows from that.

Keying by **platform** instead of **thread** is what makes this a believable bolt-on rather than a rewrite:

- **Bounded N (~3).** Claude / Codex / Cursor. No unbounded window churn.
- **The platform dimension is already known to the hook.** No new identity to invent or thread through.
- **Trivial lifecycle.** A platform is "active" (running) or it's gone. No per-thread birth/death/TTL-reap problem — which is the genuinely fiddly part of the per-thread version.

Per-thread, by contrast, inherits unbounded churn, the session-lifecycle/TTL swamp (threads don't reliably fire a clean "end"), and forces a decision about how singular `gate.json` (SoA) attaches across many pets. Out of scope here.

## What changes, by layer

The window-spawning is the easy ~20%; the **state model is the hard ~80%.** Honest map of the blast radius:

1. **`packages/contracts` (public surface).** Schema goes from one state to a **platform-keyed collection** (e.g. `{ "claude": <stateEntry>, "codex": <stateEntry>, ... }`). This is the public contract surface — per project policy it's treated as if users exist, so it's a real `schema_version` bump, not a quiet shim. (We just did schema-v4 in Phase 07, so the blast radius pattern is known.)
2. **`hook-binary.ts`.** Each hook writes **its own platform slice** rather than clobbering one file (today concurrent agents already last-writer-wins stomp the single file — keying by platform actually *improves* correctness here). Lifecycle is simple at platform granularity: slice appears when a platform's hooks go live; a platform-idle slice just renders `idle`.
3. **Renderer (the friendly part).** `PetStateFanout.swift` + `FloatingPetController` + `FloatingPetPanel` already exist — a "fanout" abstraction at all suggests one-state→many-consumers was conceptually anticipated. Spawning ≤3 `NSPanel`s each driven by its platform slice is normal AppKit. Bounded sub-problems: spatial layout (don't stack pets on top of each other) and spawn/despawn animation.

## Additional v2 design decisions (locked in this exploration)

- **Platform icon on each floating pet.** Anchor a small platform badge (Claude / Codex / Cursor mark) to the **top-left of the floating pet frame** so it's obvious which pet belongs to which platform. Cheap, high-clarity disambiguation; avoids needing distinct pet *characters* per platform at v2.
- **Menubar stays as-is — single aggregate, no fan-out.** The menubar item keeps doing single-frame "latest transition" rendering and serves **all** platforms: as state-transitions stream in from any platform, it shows the most recent one. The one nuance: it may have to **switch which pet it renders** (not just swap the single-frame activity state) when the latest transition comes from a different platform than the one it was last showing. Keeping the menubar singular keeps menubar real estate sane (multiple menubar pets is not desirable) and confines the keyed-state complexity to the floating layer.

## Sequencing / caveat

This touches the **same contract surface** Phase 07/08 are stabilizing for the Lite+SoA v1 gate. Even the "easy" platform-keyed version is a **post-v1 phase**, not a slip-in. Land v1 first; revisit as a v2 phase once schema-v4 and the v1 release have settled.

## One-line summary

Don't frame it as "multiple pets" — frame it as **"give `state.json` a platform key."** Once state is platform-keyed, the renderer's existing fanout makes ≤3 floating pets (each badged top-left with its platform icon) fall out fairly naturally, while the menubar stays a single aggregate that just switches which pet it shows on the latest transition.
