# Phase 12: Keyed-State Refactor (the v2/v3 multi-pet foundation)

**Delivery status:** Product plan — awaiting developer approval. No decomposition yet.

## TL;DR

**Goal:** Turn the single-scalar `state.json` into an `(origin, session_id)`-keyed collection behind a reducer interface, with **zero observable behavior change**, so every v2/v3 multi-pet feature (per-platform, badge-only, per-thread) is a later additive reducer rather than a second schema rewrite.

**Ships:**

- `state.json` becomes an `(origin, session_id)`-keyed collection in `packages/contracts` (schema version bump).
- A reducer interface `keyedState → renderTargets`, with the `global-aggregate` reducer as the only wired render target (collapses the collection to today's single pet).
- A second reducer (`per-platform`) implemented as a **pure, unit-tested function** — not wired to rendering — so the interface ships with two implementations and is falsified in code.
- CLI hook writer (`hook-binary.ts`) writes its own per-`(origin, session_id)` slice instead of last-writer-wins clobbering the single file.
- Clean keyed write at bumped `schema_version` (6 → 7): the CLI emits the keyed collection as the primary representation; **no legacy-scalar dual-write** (there is no in-the-wild skew window to protect — see release model below). TS `STATE_JSON_SCHEMA_VERSION` and Swift `EXPECTED_STATE_SCHEMA_VERSION` bump together in the same phase (intra-branch lockstep).
- `gate.json` override reconciled against the new model (ambient gate renders on the global-aggregate pet — no son-of-anton change).
- **`/sync` auth (`convex/http.ts`)** — close the unauthenticated public write surface before the v2 leaderboard consumes it. (Folded in by developer decision; widens the phase to the Convex stack.)

**Defers:** all visible reducers (per-platform/badge-only/per-thread *rendering*), the Settings > Customization tab, gate.json Option 1 (`origin, session_id` stamping, which is upstream son-of-anton work), and the remaining non-state-model v1 debt (gallery-ops drift, web CI/dual-install, Swift TODO remaps).

---

Codogotchi shipped v1.1.1 (Product Hunt launched). Multi-pet is a committed v2 deliverable that **changes the core data model** — today the contract is one `ActivityState` → one pet, with zero session/platform key anywhere in `packages/contracts` or the hook writer. Research on `m1ckc3s/claude-status-bar` (a menubar-only Claude activity indicator) showed a comparable shipping project already keys state per `session_id` and renders one prioritized aggregate — proving the granular key is the easy part and that "how many pets show" is a *render* choice, not a *storage* one. The forcing function: get the schema grain wrong now and we migrate `state.json` twice (once for per-platform, again for per-thread). Phase 12 pays that schema cost exactly once, at the finest grain, while changing nothing the user can see in the renderer.

The state-model refactor is the spine; it is otherwise a single-stack (contracts→CLI→Swift) phase. One cloud-stack item is folded in by developer decision: **`/sync` auth** — `convex/http.ts` is a live unauthenticated public write surface that the v2 leaderboard will consume, and closing it now (rather than in a later hygiene phase) means the cloud write contract is hardened before it gains a second consumer. It is the one deliberate exception to the single-stack, behavior-invisible framing.

**Release model (decided 2026-06-28).** No DMG / CLI / Convex release ships to users until v2 is battle-tested and released as a coordinated whole. Therefore there is **no intermediate in-the-wild version-skew window** during v2 development, and `schema_version` may be bumped freely as v2 develops. Phase 12 and all subsequent v2 phases **close out onto `origin/v2_preview`, not `origin/main`**, and intermediate phases need not be independently shippable. The one-time v1.1.1 → v2 migration (the only real skew, at GA) is explicitly a concern of the eventual **v2 release phase**, not this one.

## Phase Goal

This phase should leave the product in a state where:

- The pet, the menubar, and the gate override render **byte-identically to v1.1.1** — the renderer-facing refactor has no behavioral delta a user can observe. (The `/sync` auth change is the one intentional behavior change, on the cloud surface, not the renderer.)
- The `/sync` HTTP write surface (`convex/http.ts`) **rejects writes lacking the shared secret** — the open-internet write hole is closed before the leaderboard consumes it (identity-grade auth / spoofing prevention deferred to the leaderboard phase).
- `state.json` is an `(origin, session_id)`-keyed collection internally, written slice-by-slice by the CLI, and read through a reducer that collapses to the single aggregate pet.
- The reducer interface has **two implementations in code** (`global-aggregate` wired; `per-platform` as a tested pure function), demonstrating the seam generalizes before any UX is built on it.
- The schema-version lockstep (`STATE_JSON_SCHEMA_VERSION` ↔ `EXPECTED_STATE_SCHEMA_VERSION`) bumps 6 → 7 **together in the same phase** — a built v2_preview checkout never has a writer/reader version mismatch (intra-branch lockstep is tested).

## Committed Scope

### Keyed state model (the spine)

- `packages/contracts`: `state.json` shape moves from one scalar `ActivityState` to an `(origin, session_id)`-keyed collection; `schema_version` bump 6 → 7. No back-compat dual-write — the keyed collection is the only representation (the global-aggregate reducer reproduces the single-pet view; no legacy scalar retained).

### Reducer interface

- A `keyedState → renderTargets` reducer seam.
- `global-aggregate` reducer: wired as the sole render target; collapses the collection to one pet using a documented priority tiebreak (consistent with today's "latest transition" behavior).
- `per-platform` reducer: implemented as a **pure, unit-tested function only** — no rendering, no Settings, no spatial layout. Exists to falsify the interface.

### CLI hook writer

- `hook-binary.ts` writes its own `(origin, session_id)` slice rather than clobbering the single file (this *improves* concurrent-agent correctness vs. today's last-writer-wins).

### Reader + gate reconciliation (Swift)

- Swift decode reads the keyed collection and `EXPECTED_STATE_SCHEMA_VERSION` bumps to 7 in lockstep with the CLI. (No old-file tolerance required — within v2_preview, writer and reader always agree.)
- `gate.json` override path reconciled against the keyed model: the ambient gate continues to override the **global-aggregate** pet. **No change to the read-only `.son-of-anton` subtree.**

### Cloud write surface (folded in)

- `/sync` (`convex/http.ts`): **shared-secret hardening** — the CLI sends a pre-shared secret header; Convex verifies it against an env var and rejects callers without it, closing the open-internet write hole before the v2 leaderboard reuses the surface. **Not full identity auth** — binding writes to a verified user (and stopping `profile_id` spoofing) requires the enroll/token handshake that is leaderboard-era work and is deferred. This is the sole cloud-stack deliverable and the sole intentional behavior change.

## Explicit Deferrals

- **Visible reducers (per-platform / badge-only / per-thread *rendering*)** — each is a feature with its own UX surface (spatial layout, spawn/despawn, Settings plumbing); deferred to v2/v3 feature phases so they're reviewed as features, not smuggled into a refactor.
- **Settings > Customization tab** — the render-policy picker is a feature-phase deliverable; Phase 12 ships no user-facing toggle.
- **gate.json Option 1 (`origin, session_id` stamping)** — requires an upstream change to `cesarnml/son-of-anton` (the read-only subtree) plus a stable per-thread session id at delivery time; deferred to the v3 per-thread phase. Phase 12 uses Option 2 (ambient gate on the aggregate), which needs no SoA change.
- **Gallery-ops drift** (`convex/schema.ts` phantom `P12.01` comment, `sizes: v.any()`, dual zip/CDN render path, undocumented operator levers) — different stack (Convex/web); dedicated hygiene phase before the leaderboard reuses that surface. (Note: `/sync` auth, which lives on the same stack, is **not** deferred — it was folded into committed scope above.)
- **web dual-install + web tests off root CI** — different stack; hygiene phase.
- **Swift TODO remaps** (`editing`, `searching`, `web_search`, `verifying`, `git_ops`) — art/renderer cleanup unrelated to the state model.
- **One-time v1.1.1 → v2 migration / gray-out safety** — the only real version skew is the single GA jump from v1.1.1 (schema 6) to v2 (schema ≥ 7). Handling it (reader tolerance, coordinated release, or "update both" messaging) is a deliverable of the eventual **v2 release phase**, not Phase 12 — because nothing ships to users until then.

## Exit Condition

Build the v2_preview checkout and **see no difference in the pet**: it animates, the menubar updates, and SoA delivery gates override exactly as they did on v1.1.1. Under the hood, `state.json` is now an `(origin, session_id)`-keyed collection (`schema_version: 7`) written slice-by-slice by the CLI and read through the `global-aggregate` reducer. A test suite demonstrates: (1) the reducer interface with two implementations (`global-aggregate` wired, `per-platform` pure-tested); (2) writer/reader version lockstep at 7 (no intra-branch mismatch). Separately, an unauthenticated `POST` to `/sync` is now **rejected** where it previously succeeded — the one demonstrable behavior change, on the cloud surface. No web, Settings, Swift-art, or son-of-anton files were touched. (Cross-version v1→v2 migration safety is explicitly out of scope — deferred to the v2 release phase.)

## Retrospective

`required` — introduces a durable architectural boundary (the keyed schema + reducer seam that every v2/v3 feature phase builds on) and changes downstream phase assumptions; capture the cross-channel skew strategy and whether it held.
