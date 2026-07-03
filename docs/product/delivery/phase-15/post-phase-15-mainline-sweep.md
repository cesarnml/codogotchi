# Post-Phase 15 mainline sweep

> **Status (2026-07-03): direct-to-main QC window CLOSED at this commit.** Phase 15 closed at `22345b4b` (docs: close out all 5 phase-15 requires-human-review AOs). Everything below landed directly on `main` afterward — 39 commits of Phase 15 review-gap fixes and regression prevention, all within the same session (2026-07-03 dogfood cycle). Work resumes under structured SoA phase delivery with **Phase 16**.

Reference for agents and maintainers: what shipped directly on `main` after the Phase 15 ticket stack closed at `22345b4b`.

**Sweep command:** `git log --reverse --date=short --pretty=format:'%h %ad %s' 22345b4b..HEAD`

**Date range:** 2026-07-03 (39 commits, single-day QC landing).

**Stance:** Phase 15 shipped the "pet per active agent thread" feature (per-session window fan-out, session cap, eviction/promotion, per-session menus/tooltips), and the advisory-observation triage identified 12 spec gaps (codogotchi-28 through codogotchi-39) that arose during dogfood. All 12 gaps are close-enough-to-land issues: each has a narrow fix (2–5 lines or a test-coverage gap) and a clear spec intent. This ledger consolidates those 12 fixes plus one pre-phase-15 item (session rename path not wired to Minimalist mode) and one infrastructure fix (xcodegen Source scan excluding .soa/) directly to main, bundled as a single "post-phase QC" delivery using the same ledger capture workflow from the Phase 14 retrospective.

---

## Change buckets

| Bucket | Commits | What changed | Why it matters |
| --- | --- | --- | --- |
| Session rename / Minimalist mode wiring | `d99a7e19` | Minimalist mode's session-rename read/write path was left unimplemented in Phase 15 — the UI rendered the old rename text input but it never wired through to `StateJsonWriter.updateSessionLabel`. | This was pre-phase-15 work that didn't land when minimalist session-tooltip was wired, discovered during post-phase spec review. Minimalist users can now rename sessions, achieving parity with Own mode. |
| Mode transition teardown | `003a95bd`, `cd4116dc`, `94b532bb`, `3cfeb596` | Enabled Session Pets on an own-mode origin was not dismissing the stale plain-origin window; Combined→Minimalist was not dismissing the Combined window; Combined→Own was not dismissing the Combined window; Session Pets toggle off was not dismissing all session-keyed windows. All four were missed in the Phase 15 pool refactor's teardown branches. | These gaps left orphaned windows on screen and broke the mode-switch contract. Each is 2–5 lines of condition gating in `FloatingPetWindowPool.update()`. |
| Session menus and labels | `ec408445`, `2fc7dd99` | Session-keyed windows in the menubar dropdown were showing raw UUID instead of the session label; dropdown item rows did not label which session each pet was. | Without labels, a user with multiple concurrent sessions saw a dropdown full of identical-looking pets with no visual distinction, making it impossible to toggle hide/show or navigate intentionally. |
| Session attention bubbles (Focus/dismiss fan-out) | `47375d20`, `9421efba` | When a user clicked "Focus" or "Dismiss" on a session's attention bubble, only that one window's bubble was cleared — sibling sessions on the same platform kept their bubbles, appearing to still need attention. | The spec intent was: Focus/Dismiss on a platform's session affects all sessions on that platform (at-source clearing, matching the source event's platform). Bubble state is now broadcast to all sibling windows. |
| Session-cap eviction frame inheritance | `0fa51fd1`, `0620f5fc` | When cap pressure evicted an idle session and promoted an active newcomer, the newcomer's window did not inherit the evicted session's frame—it appeared at the default spawn position instead. | Preserving the visual position on window swaps (idle→active promotion) is a UX contract. Matches the existing grandfather-activation behavior. |
| Grandfather session initialization | `42a81dbe`, `e2ebe368`, `e6348137`, `14fedcca` | When a user toggled Session Pets on for the first time on a platform already running, the incumbent pet's session was not initialized as Session 1; the PerPlatformGateReader wasn't aware of per-session gate files; four spec ambiguities in the grandfather gate-resolution caused correctness bugs. | Grandfather semantics are: the currently-rendering pet becomes Session 1; if no pet was rendering (e.g., off-mode origin), no grandfather. Gate reader needed session-awareness to route per-session badges correctly. Code review found bugs in tier-1 priority (cap tie-break, single-session fallback). |
| Gate reader refactoring and session-awareness | `8c831cd1`, `10a3d5b4`, `d9c0e0b0`, `3f66fcbe` | Removed dead `read()`/`readPerSession()` entry points; gated the legacy flat-file fallback on single render key (not single origin); consolidated three per-tick `state.d/` scans into one; made `PerPlatformGateReader` session-aware. | `LivePollingDriver` and pool logic were calling legacy fallback path unguarded in multi-session scenarios, risking misattribution. Single scan reduces CPU. Session-keyed gates are Phase 15's new shape. |
| Force-Idle badge/conflict-bubble clearing | `fa57f111`, `0c4cb4b8` | Clicking "Force Idle" on a window (right-click menu) was not clearing the SOA gate badge or conflict (speaker emoji) bubble — they remained visible, appearing to show stale context even though the platform itself had gone idle. | The spec intent: Force Idle is an escape hatch that clears all transient state (attention, delivery context, conflict). Badge and bubble are part of that transient state. |
| Pet visibility persistence | `1ba9bc32`, `699d20c6` | When a user hid a pet and restarted the app, the pet was not restored as hidden—it re-spawned as visible on the next snapshot tick. | The hide/show state was not being persisted to UserDefaults. Matches the existing frame-position persistence contract. |
| Hide and cap-incumbency interaction | `13beac0a`, `64fc8a85`, `2ef6c338`, `ae1ae7bd` | When a user hid a session and then new activity caused eviction/promotion across the cap boundary, the hidden session was incorrectly counted as eligible for tie-break (slowing down active sessions' wins); the hidden session's slot was not released after it lost the cap fight; hidden sessions appeared in the menubar dropdown even though they were hidden. | Hide was implemented as a visibility gate but not integrated into the capacity and eviction logic. A hidden session should be skipped during selection (not compete for the cap) and dropped from the menu entirely once genuinely evicted. Three separate narrow fixes. |
| Infrastructure (xcodegen Source scan) | `b1a5d02b` | The Xcode project's `xcodegen` Sources glob was including `.soa/` directory, causing stale compiled Swift files from prior son-of-anton deliveries to leak into the build. | The `.soa/` subtree is read-only and should never contribute Source files to the app's build. Exclusion pattern prevents accidental compilation of orphaned protocol/stub files. |

---

## Commit index

| Date | Commit | Summary |
| --- | --- | --- |
| 2026-07-03 | `d99a7e19` | Wire session rename read/write path into Minimalist mode. |
| 2026-07-03 | `003a95bd` | Dismiss stale window on any transition away from combined mode. |
| 2026-07-03 | `cd4116dc` | Record phase-15 combined-mode teardown gap (codogotchi-28). |
| 2026-07-03 | `94b532bb` | Dismiss stale window on Session Pets toggle in either direction. |
| 2026-07-03 | `3cfeb596` | Record phase-15 session-pets toggle teardown gap (codogotchi-29). |
| 2026-07-03 | `ec408445` | Label session-keyed menubar pet items with session name, not raw UUID. |
| 2026-07-03 | `2fc7dd99` | Record phase-15 session-label menubar dropdown gap (codogotchi-30). |
| 2026-07-03 | `47375d20` | Dismiss all sibling session bubbles on Focus/X for a platform. |
| 2026-07-03 | `9421efba` | Record phase-15 session-attention Focus/dismiss fan-out gap (codogotchi-31). |
| 2026-07-03 | `0fa51fd1` | Inherit evicted session's frame for the incoming active session. |
| 2026-07-03 | `0620f5fc` | Record phase-15 session-cap eviction frame-inheritance gap (codogotchi-32). |
| 2026-07-03 | `42a81dbe` | Grandfather the incumbent pet as Session 1 on session-pets activation. |
| 2026-07-03 | `e2ebe368` | Make PerPlatformGateReader session-aware. |
| 2026-07-03 | `e6348137` | Fix 4 correctness bugs found by code-review in the grandfather gate. |
| 2026-07-03 | `fa57f111` | Clear SOA badges and conflict bubble on Force Idle. |
| 2026-07-03 | `0c4cb4b8` | Record phase-15 Force-Idle badge/bubble gap (codogotchi-33). |
| 2026-07-03 | `14fedcca` | Record phase-15 session-pets grandfather/activation spec gap (codogotchi-34). |
| 2026-07-03 | `d9c0e0b0` | Scan state.d/ once for both gate reader views. |
| 2026-07-03 | `d14abf1d` | Grandfathered session inherits the collapsed plain pet's frame. |
| 2026-07-03 | `10a3d5b4` | Gate legacy fallback on single render key, not single origin. |
| 2026-07-03 | `3f66fcbe` | Record phase-15 grandfather-frame-inheritance spec gap (codogotchi-35). |
| 2026-07-03 | `8c831cd1` | Remove dead read()/readPerSession() entry points. |
| 2026-07-03 | `1ba9bc32` | Persist per-pet hide/show visibility across app restarts. |
| 2026-07-03 | `699d20c6` | Record phase-15 pet-visibility persistence gap (codogotchi-36). |
| 2026-07-03 | `a7fe1e93` | Merge branch 'session-aware-gate-reader'. |
| 2026-07-03 | `e28cb5c2` | Gate post-prune slot promotion to in-flight sessions. |
| 2026-07-03 | `c309a86c` | Record phase-15 prune-vs-passive-expiry promotion gap (codogotchi-37). |
| 2026-07-03 | `37180965` | Record manual dogfood verification for codogotchi-37. |
| 2026-07-03 | `b1a5d02b` | Exclude .soa/ from xcodegen Sources scan. |
| 2026-07-03 | `13beac0a` | Stop hide from stripping cap-slot incumbency. |
| 2026-07-03 | `64fc8a85` | Record phase-15 hide-strips-cap-incumbency gap (codogotchi-38). |
| 2026-07-03 | `2ef6c338` | Drop hidden sessions from the menu once they lose the cap fight. |
| 2026-07-03 | `ae1ae7bd` | Record phase-15 hide-then-genuinely-evicted gap (codogotchi-39). |

---

## Review-gap ledger capture

All 12 advisory-observation gaps from phase-15 closeout (codogotchi-28 through codogotchi-39) were recorded using the established post-phase QC workflow (fix + paired `docs(review-gaps)` commit). Additionally, one spec ambiguity in the grandfather gate (codogotchi-37, correctness bugs found by code-review in PR #152) received manual dogfood verification before landing.

## Follow-up recommendations

1. **This file closes the Phase-15→Phase-16 mainline window.** New work resumes under structured SoA phase/ticket delivery for Phase 16.
2. The gate reader's three separate `state.d/` directory scans (original `readPerPlatformDirectory`, legacy `newestFile` fallback, new `PerPlatformGateReader.read`) remain unoptimized; consolidating into one shared listing is a reasonable cleanup for Phase 16 if it's already touching this code path.
3. Phase 16 should extend per-session gate routing (now in place via `PerPlatformGateReader`) to the session-attention/bubble routing currently keyed only by platform — per-session attention badges are out of scope for Phase 15 but a natural continuation of this session-awareness work.

## Suggested commit subject

`docs: capture post-phase-15 mainline sweep and QC landing`
