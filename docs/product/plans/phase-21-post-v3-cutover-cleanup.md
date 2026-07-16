# Phase 21: Post-v3 Cutover Cleanup

**Delivery status:** Stack delivered 2026-07-15 (PRs #190–#194) — awaiting developer closeout onto `v3_preview`. Delivery docs at `docs/product/delivery/phase-21/`.

## TL;DR

**Goal:** Eliminate Phase 17–18 cutover leftovers and dual-era seams in the menubar app — with a hard behavior freeze — so later work does not keep paying shotgun tax on dead protocols, duplicate allocators, and shadow tooling that no longer ships.

**Ships:**

- Shadow compare/proxy/logger trio **deleted** from the app (and tests that exist only to exercise them removed or rewritten away).
- Empty `Menubar.xcodeproj` husk removed; Derive/Pool doc comments scrubbed of stale “until P18.xx / not yet” archaeology.
- `pruneMenuTitle` collapsed to a constant; `foldedSessionDisplay` pipeline removed end-to-end when prune was the sole consumer (kept only if a real other consumer remains).
- Production window/panel protocols expose **one** prompt-timer push (`presentation`); raw `applyPromptTimerStatus` off the production protocol surface (private helpers allowed so timer feel stays unchanged).
- Single session-number ownership: throwaway `SessionNumberAllocator` on the prune path gone; assign/reuse/release outcomes unchanged vs today’s derive-backed allocator.
- Local-only dogfood DMG at closeout; retrospective written.

**Defers:** Flat-gate production fallback removal; Own/Minimalist shared persist/timer extraction; fixing waived Phase 18 shadow-soak / P18.06 `XCTSkip` gaps; ripping Minimalist; collapsing menubar vs pool consumers; any intentional user-visible change.

---

Phases 17–18 delivered surface convergence and `derive → diff → apply`; Phases 19–20 shipped fold identity and sticky slice clocks on that pipeline. After P18.07 the imperative pool engine and live shadow tick were already gone, but the app still carried Phase 18–retained shadow utilities in `Sources/Pool`, dual prompt-timer protocol methods, a half-dead fold-display→prune-title pipe, stale ticket comments, an empty pre-rename Xcode project husk (already absent on `v3_preview` by delivery time), and a class allocator constructed only so prune could ignore it. Phase 21 cleared those leftovers under the same behavior bar as Phase 16.

## Phase Goal

This phase should leave the product in a state where:

- Developers looking at `Sources/Pool` no longer find shadow-compare machinery that is not part of the live update path; the app binary does not compile that trio.
- Protocol and DTO surfaces match the live tick: one prompt-timer push vocabulary on the production path; prune titles do not thread discarded fold-display strings; Derive docs describe present-tense architecture.
- Session prune and derive share one numbering owner — no throwaway empty allocator on the prune path — with numbering and prune disk side effects observably unchanged.
- Daily-driver behavior matches the pre-phase dogfood build: prompt timer cadence/truthfulness, prune/rename/hide menus, session numbers, Own and Minimalist skins all behave as before.

## Committed Scope

### Program invariants (binding on this phase)

- **Behavior bar: freeze + bug fixes.** Zero intentional user-visible change. Full existing suite green per ticket (minus tests deleted because their subject was deleted). Genuine pre-existing bugs exposed by the cleanup are fixed in separate commits with review-gap ledger entries — not expanded phase scope.
- **No big-bang.** Every ticket independently landable and behavior-neutral.
- **Leftover elimination only.** Do not treat product/QA decisions (Minimalist removal, soak-gap fixes, menubar/pool consumer merge) as cleanup.

### Shadow tooling deletion

- Delete `PoolShadowComparator`, `RecordingFloatingPetWindowControllingProxy`, and `ShadowDivergenceLogger` from the app target.
- Remove or rewrite tests whose sole purpose was that harness; do not leave stubbed empty test files that imply live shadow still exists.
- Document in the retrospective that Phase 18 waived reverse-shadow soak and Phase 21 deleted the last shadow utilities without re-introducing a soak gate.

### Project husk + comment scrub

- Delete the empty `apps/menubar/Menubar.xcodeproj` husk (Codogotchi.xcodeproj remains the real project).
- Scrub Derive/Pool (and related) comments that still claim “Always empty until P18.03”, “does not yet emit …”, or other ticket-step archaeology that contradicts landed behavior. Present-tense docs only; no behavior change.

### Fold display / prune title leftover kill

- Collapse `FloatingPetHidePrompt.pruneMenuTitle(foldedSessionDisplay:)` to the bare prune title constant (or direct use of `pruneTitle`).
- Audit `foldedSessionDisplay` end-to-end (DesiredWindow → apply → views → prompts/alerts). If prune was the only consumer after P19.04, remove the field and push path entirely. If another real consumer remains, keep only that consumer and stop threading discarded parameters into prune UI.

### Prompt-timer protocol surface

- Production protocols used by `PoolApply` expose presentation push only — not a parallel unused status push.
- Private view/controller helpers for heartbeat / override clearing are allowed when needed so **on-screen timer labels keep current cadence and truthfulness** (no intentional change to elapsed display, wipe/reset, or chip visibility).
- Tests that asserted status-vs-presentation override semantics are rewritten to the remaining public/private surface, not deleted in a way that loses the regression.

### Allocator / Pruner unification

- Eliminate the dual free-list implementations as a prune-path fiction: no fresh empty class allocator constructed only so `.release` is a no-op.
- After Prune Session (and any sibling path with the same pattern), session numbers continue to assign/reuse exactly as with today’s derive/`PoolMemory` owner — no double-release, no renumber of live sessions.
- Disk slice / label / retrieved-title cleanup from prune remains.

### Closeout

- Package a local dogfood DMG and install as daily driver.
- **No public GitHub release** for this phase (behavior-neutral hygiene; public ship remains Track 2 / v3).
- Write the phase retrospective (required — see below).

## Explicit Deferrals

- **Flat-gate production fallback removal** — launch cleanup already deletes flat files; keeping the read fallback is a migration/compatibility belt for old installs and tests, not cutover noise. Not an exit gate.
- **Own/Minimalist shared persist/timer extraction** — live dual-skin reorganization, not dead-code elimination; large diff, weak leftover signal.
- **Waived Phase 18 reverse-shadow soak / P18.06 `XCTSkip` known gaps** — product/QA debt, not leftovers; fixing them is a behavior or policy phase.
- **Ripping Minimalist / collapsing menubar vs floating-pool consumers** — product decisions, out of scope.
- **Wiring floating-pet `visualMode` / desaturated failure from derive** — would be an intentional visual behavior change.
- **Public notarized release / Sparkle** — Track 2.

## Exit Condition

The phase is done when all of the following are demonstrably true on `v3_preview`:

1. **Shadow gone:** grep under `apps/menubar` finds no `PoolShadowComparator` / `RecordingFloatingPetWindowControllingProxy` / `ShadowDivergenceLogger` production or orphaned-only test harness left as “live architecture.”
2. **Husk + docs:** `Menubar.xcodeproj` is gone; Derive/Pool comments no longer claim unfinished P18.0x placeholders for landed fields.
3. **Fold/prune leftover:** prune UI uses the bare prune title; discarded `foldedSessionDisplay` parameters are gone; the field/push path exists only if a non-prune consumer remains.
4. **One timer push on production protocols:** `PoolApply`’s push path and window/panel production protocols do not advertise unused `applyPromptTimerStatus`; timer feel matches pre-phase dogfood.
5. **One numbering owner:** prune path does not construct a throwaway empty session-number allocator; numbering and prune outcomes match pre-phase behavior under the freeze bar.
6. **Suite + dogfood:** existing suite green (adjusted for deleted subjects); local DMG installed as daily driver with no unexplained regressions; retrospective filed.

## Retrospective

`required` — Phase 18 waived reverse-shadow soak and this phase deletes the last shadow utilities plus dual-era seams; capture that decision tree and any freeze-adjacent surprises for later Track work.
