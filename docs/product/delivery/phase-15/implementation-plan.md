# Phase 15 — Per-Session Pets (Pet Per Active Agent Thread)

> Render one pet panel per active agent session (`session_id`) on a platform in Own and Minimalist modes, gated behind an opt-in per-platform setting, with per-session labeling, rename, aging, capacity, and a conflict signal.

## Epic

Product plan: [`docs/product/plans/phase-15-per-session-pets.md`](../../plans/phase-15-per-session-pets.md). Decision source of truth: [`notes/private/phase-15-per-session-pet-extension-kickoff.md`](../../../../notes/private/phase-15-per-session-pet-extension-kickoff.md).

## Product contract

When this phase is complete, a user can open Settings > Platform Settings, enable **Session Pets** for a platform in Own or Minimalist mode (cap defaulting to 3), run three concurrent agent sessions on that platform, and see three pet panels appear labeled "Session 1/2/3", each rendering that platform's assigned (or Default) pet. Renaming a panel (right-click → rename, ≤24 chars) sticks for that session's lifetime; hovering its animation badge after a short delay surfaces that thread's last submitted prompt. Manually pruning a session (right-click → Prune Session) destroys the panel and deletes its state, freeing its number back to a per-platform pool so the next new session reclaims the lowest free number. Pushing past the cap de-renders an idle/standby panel before an active one; when every remaining panel is actively working a rate-limited bubble appears on the longest-lived panel and deep-links to Settings, and the blocked session pops into a real panel the instant a slot frees. Flipping the platform to Minimalist swaps pet panels for badge strips carrying the same per-session labels. A user who upgrades and never touches the new setting sees exactly what they saw before. The app version reads 2.2.0; no DMG is cut this phase.

## Grill-Me decisions locked

- **Composite `origin:session_id` window key with an explicit collapse** → the reader emits full per-session granularity `[origin:session_id → StateSnapshot]` and a pure `resolveRenderKeys` step reduces it to the render set by mode + setting. Combined origins fold to `"combined"`; Own/Minimalist with session-pets-off fold each origin's sessions to the last-writer-wins winner keyed by plain `origin`; Own/Minimalist with session-pets-on keep each `origin:session_id` as its own key. The pool keys windows by this resolved key **uniformly** — the "session-enabled?" branch lives in exactly one place (key derivation). Rationale: this is the day-one architecture; collapsed keys are byte-identical to today's keys, so the existing pool invariants (last-active immunity, TTL clock, hide-set, gate-badge join) and their tests become the regression net.
- **`session-labels.json` is a Swift-owned sidecar** → rename persists `{ "origin:session_id": "label" }` in a new app-owned file, read-merge-written by the app. No CLI change; the `state.d` slice stays CLI-single-writer, avoiding a two-writer race. The CLI `writeSliceAtomic` full-overwrite would have stripped/clobbered a label written into the slice, so the slice is not a viable host. Rationale: the label is UI state the CLI never reads — keeping it app-side is the correct boundary, not tech debt.
- **Session number free-list is in-memory** → a per-platform lowest-free-number allocator, rebuilt at launch. Durable identity is the persisted rename label; the auto-number is a disposable default whose cross-restart stability is low value and not worth a second persisted store to reconcile.
- **Cap eviction is a reversible de-render, not a delete** → when an origin has more live session slices than its cap, the pool renders the top-N by priority and holds the rest as pending. The held session's slice stays on disk (the CLI writes it regardless), so blocked-session tracking needs no new persistence — it is the pool's in-memory selection policy. Promotion fires the instant a rendered slot frees. Only manual Prune and TTL actually delete.
- **Eviction priority** (most- → least-evictable, grounded against `ActivityState.swift`): `idle`/`standby` → `errored` → `waiting_for_input` → any in-flight active state (never auto-evicted).
- **Blocked signal is the P15.07 ↔ P15.08 seam** → the selection policy (P15.07) emits an "all-remaining-active, newcomer blocked" signal; the conflict bubble (P15.08) consumes it. Separate render surface and test strategy.
- **Scan consolidation in scope as P15.02**; **version-only bump to 2.2.0**, no DMG this phase.
- **`session_cap` representation** → stored as `Int` in `customization.json` with `0` = Unlimited (1 is not offered, so 0 is a free sentinel); absent-but-enabled resolves to the default 3. `customization.json` stays `schema_version: 1` (additive, unknown values already tolerated).
- **No state-schema lockstep change** → `STATE_JSON_SCHEMA_VERSION` / `EXPECTED_STATE_SCHEMA_VERSION` are untouched this phase.

## Ticket Order

1. `P15.01 Contracts: customization.json session-pets fields`
2. `P15.02 Refactor: consolidate state.d directory scans`
3. `P15.03 Per-session reader + resolveRenderKeys collapse`
4. `P15.04 Pool per-session window fan-out`
5. `P15.05 PlatformSessionBadge + in-memory free-list numbering`
6. `P15.06 Rename + last-prompt tooltip`
7. `P15.07 Selection policy: cap, eviction, prune, session-keyed TTL`
8. `P15.08 Conflict bubble + rate limit + Settings deep-link`
9. `P15.09 Settings > Platform Settings UI`
10. `P15.10 Docs sweep + v2.2.0 bump + retrospective`

## Ticket Files

- `ticket-01-contracts-session-pets-fields.md`
- `ticket-02-consolidate-state-scans.md`
- `ticket-03-per-session-reader-resolve.md`
- `ticket-04-pool-per-session-fanout.md`
- `ticket-05-session-badge-numbering.md`
- `ticket-06-rename-tooltip.md`
- `ticket-07-selection-policy-prune-ttl.md`
- `ticket-08-conflict-bubble.md`
- `ticket-09-settings-platform-settings-ui.md`
- `ticket-10-docs-retrospective.md`

## Exit Condition

A developer opens Settings > Platform Settings, enables session pets for a platform in Own mode (cap defaulting to 3), runs three concurrent agent sessions on that platform, and watches three pet panels appear labeled "Session 1/2/3", each rendering that platform's pet. Renaming a panel (≤24 chars) sticks for that session; hovering its animation badge surfaces the thread's last prompt. Pruning a session frees its number back to the pool, and the next new session reclaims the lowest free number. Pushing past the cap yields an idle/standby panel before an active one; when all three are actively working, a rate-limited bubble appears on the longest-lived panel and deep-links to Settings, and the blocked session pops in the moment one finishes. Flipping the platform to Minimalist swaps the pet panels for badge strips carrying the same per-session labels. A user who simply upgrades and never touches the new setting sees exactly what they saw before. The app version reads 2.2.0.

## CI Baseline

> Recorded at phase start (`445ccb36`, the SHA where P15.01 branches from main): `bun run ci:quiet` **PASSED** — 704 tests, 0 failures. Pre-existing failure count: **0**. Any CI failure introduced by a Phase 15 ticket is therefore newly introduced and blocks that ticket.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- P15.03 must feed the pool a byte-identical per-origin render set (session-pets-off collapse) — every existing `FloatingPetWindowPoolTests` case must still pass unchanged. A green existing suite is the gate for the composite-key foundation.

## Explicit Deferrals

- **Session-scoped pet identity ("pet collection per platform")** — distinct pets per session. No `assignments.json` `scope` field is added; all session panels on a platform render the same pet.
- **Session-linked SoA gate/ticket badges** — per-session SoA gate/animation attribution across codogotchi + upstream `cesarnml/son-of-anton`. SoA gate/badges continue to resolve per-platform this phase; explicit post-Phase-15 follow-up shaped by the retrospective.
- **Combined-mode session-count signal** — rejected outright, not parked.
- **True session-end detection** — TTL + manual prune is the accepted reaping contract; no new cross-platform "session ended" signal.
- **DMG / notarized release** — version-only bump this phase; the dmg is a separate human-gated ritual.
- **CLI slice schema changes** — the CLI stays out of Phase 15; the label lives in the Swift-owned sidecar.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- P15.03's collapse feeding a non-byte-identical render set (existing pool tests regress) — stop and reconcile before P15.04.
- Ambiguous eviction/priority behavior where the right action against real `ActivityState` values is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Phase 15 introduces the first session-scoped lifecycle (free-list numbering, per-session rename persistence, priority eviction, rate-limited conflict bubble) and deliberately leaves a named cross-repo follow-up (session-linked SoA gate attribution). Durable learning and downstream assumptions are likely.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-15-per-session-pets-retrospective.md`
