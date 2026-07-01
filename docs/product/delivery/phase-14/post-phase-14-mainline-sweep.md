# Post-Phase 14 mainline sweep

> **Status (2026-07-01): direct-to-main window CLOSED at this commit.** Phase 14 closed at `e07c84af` (v2.1.0). Everything below landed directly on `main` afterward — 46 commits of Minimalist-mode hardening, phase-14 review-gap fixes, and upstream SoA session-attribution wiring, plus this session's own direct-to-main work bringing per-origin SoA gate/ticket badges to parity with the per-platform pool phase-13/14 already shipped. Work resumes under structured SoA phase delivery starting with **Phase 15 (pet per active agent thread)**.

Reference for agents and maintainers: what shipped directly on `main` after the Phase 14 ticket stack closed at `e07c84af` (`v2.1.0`, PRs [#139](https://github.com/cesarnml/codogotchi/pull/139)–[#147](https://github.com/cesarnml/codogotchi/pull/147)).

**Sweep command:** `git log --reverse --date=short --pretty=format:'%h %ad %s' e07c84af..HEAD`

**Date range:** 2026-06-30 through 2026-07-01 (46 commits), plus this session's uncommitted gate-badge work on top.

**Stance:** the Phase 14 retrospective flagged two explicit deferrals — Minimalist-mode gate badges and upstream SoA session attribution — as blocked, not scoped, for Phase 15. Both blockers cleared on `main` in this window (son-of-anton Phase 17's direct-gate-write landed origin/session-tagged `state.d/` files; this session wired the codogotchi side up to consume them), which is exactly the kind of drift this ledger exists to catch before a new phase starts building on top of it.

---

## Change buckets

| Bucket | Commits | What changed | Why it matters |
| --- | --- | --- | --- |
| Minimalist mode rewrite (badge composition, strip, sizing) | `6c35389b`, `25a0881a`, `aa23cac0`, `67891a4e`, `5ad6e099`, `47fb8c0f`, `66f5e21e`, `aa1168a1`, `70ccd3b5`, `4dea4798`, `4ca3b67d`, `d74ce5c9`, `6e0e0bd3`, `9a80f9fd`, `218e1676`, `9ed36a98`, `f9d9885d`, `7138a990`, `4557ad55`, `e3bb8879`, `32a2a737`, `9a759b5b`, `3bb08ccd`, `9695334d`, `654239e0` | Rebuilt the Minimalist floating panel from a single shape-shifting window into two independent panels (badge strip + attention bubble, mirroring Own mode), composed the strip from the existing `AnimationBadgeView`/`AnimationLabelPillView` instead of a bespoke view, added an explicit badge-size slider, fixed drag stutter and right-edge clamping, added right-click "Hide panel" and "Force Idle" affordances, and polished the menu-bar dropdown and Customization tab layout. | Phase 14 shipped Minimalist mode as an MVP; this is the hardening pass that made it production-quality. The badge-composition rewrite (`6c35389b`/`67891a4e`, PR #148) is the piece Phase 15's gate-badge work builds directly on top of — it's why `MinimalistBadgeView` was a clean host for the new `GateBadgePanel` this session. |
| SoA session attribution + per-platform gate/context consumption | `d9acec9d`, `297cbf65`, `c52a5bb0`, `8f74fc4e`, `01f34adc`, `7efbaea5` | son-of-anton's hook binary started writing `active-session.json` (origin + session_id) under `.soa/`, first to the checkout root and then corrected to the canonical main-worktree root so linked worktrees resolve consistently; codogotchi's `LivePollingDriver` gained a first pass at reading per-platform+session `.gate.json`/`.context.json` files from `state.d/`, falling back to the legacy flat files. | This is the upstream half of the "SoA gate badges in Minimalist mode" deferral from the Phase 14 retrospective. `297cbf65` added the *reading* of per-origin gate/context files, but only picked the single globally-newest one and never wired the result to any window — this session's work (below) closes that gap. |
| Phase 14 review-gap fixes (post-closeout QC) | `e1910561`, `192710ad`, `590c9922`, `07661086`, `70ea4cdf`, `c05a2403`, `99b1b29e`, `6a492a8b`, `1ebbf407`, `752c0429`, `ccd4e011`, `13bb31df`, `a137940c`, `5a35d675`, `a8534a88` | Resolved the phase-14 advisory-observation triage backlog: surfaced assignment-persistence errors instead of failing silently, fixed a stale window left behind on Own↔Minimalist mode switches, corrected the combined window's badge to follow the active (non-idle) platform rather than staying pinned, reworked the Pet tab layout/popover/description alignment across three iterations, and moved pet-spritesheet decoding off the main thread. Each fix has a paired `chore(delivery)` commit recording the review-gap ledger entry. | This is exactly the "post-phase QC capture" workflow from the project's own review-gap ledger design — each fix is traceable to a specific advisory observation from Phase 14's close, not ad hoc mainline drift. |

---

## Commit index

| Date | Commit | Summary |
| --- | --- | --- |
| 2026-06-30 | `e1910561` | Resolve phase 14 advisory observations [tao]. |
| 2026-06-30 | `192710ad` | Record phase 14 advisory observation triage. |
| 2026-06-30 | `590c9922` | Show assignment persistence errors. |
| 2026-06-30 | `07661086` | Tear down stale window on own↔minimalist mode switch. |
| 2026-06-30 | `70ea4cdf` | Record phase-14 review-gap for minimalist mode switch. |
| 2026-06-30 | `c05a2403` | Add promotion-queue candidate for enum-case transition gap. |
| 2026-06-30 | `99b1b29e` | Badge combined window with active platform when not idle. |
| 2026-06-30 | `6a492a8b` | Record phase-14 review-gap for combined-window badge branch. |
| 2026-06-30 | `1ebbf407` | Pet tab layout, multiselect assign popover, icon-only pills. |
| 2026-06-30 | `752c0429` | Record phase-14 review-gap for pet tab layout and popover fixes. |
| 2026-06-30 | `ccd4e011` | Pin descLabel vertical hugging so description stays top-aligned in equal-height rows. |
| 2026-06-30 | `13bb31df` | Always render badge pills row, bottom-anchored, so description and pills align consistently. |
| 2026-06-30 | `a137940c` | Record phase-14 review-gap for 3-attempt description/pills alignment fix. |
| 2026-06-30 | `5a35d675` | Move pet-spritesheet decode off the main thread on assignment. |
| 2026-06-30 | `6c35389b` | Compose MinimalistStripView from AnimationBadgeView + AnimationLabelPillView. |
| 2026-06-30 | `25a0881a` | Use isHidden for pill visibility; revert AttentionBubbleView promotion [subagent-review]. |
| 2026-06-30 | `aa23cac0` | Record triage-standalone outcome for PR 148 (minimalist badge composition). |
| 2026-06-30 | `67891a4e` | Compose MinimalistStripView from existing badge/bubble views (#148). |
| 2026-06-30 | `5ad6e099` | Merge branch 'main' into fix/minimalist-badge-composition. |
| 2026-06-30 | `47fb8c0f` | Preserve pet-panel size when minimalist strip is dragged. |
| 2026-06-30 | `66f5e21e` | Redesign MinimalistStripView for platform-linked panels. |
| 2026-06-30 | `aa1168a1` | Content-tight minimalist strip + embedded draggable attention bubble. |
| 2026-06-30 | `d9acec9d` | Write active-session.json under .soa dir in hook-binary. |
| 2026-07-01 | `70ccd3b5` | Prevent bubble growth, reduce drag stutter, fix right-edge positioning. |
| 2026-07-01 | `4dea4798` | Minimalist strip — bubble growth, drag stutter, right-edge positioning (#fix). |
| 2026-07-01 | `4ca3b67d` | Prevent bubble growth, reduce drag stutter, fix right-edge positioning. |
| 2026-07-01 | `d74ce5c9` | Remove debug border from MinimalistStripView. |
| 2026-07-01 | `6e0e0bd3` | Scale minimalist badge with saved pet-panel size. |
| 2026-07-01 | `9a80f9fd` | Explicit Minimalist badge-size slider + combined-minimalist windowing. |
| 2026-07-01 | `218e1676` | Combined-minimalist checkbox restyles the Combined window, not Minimalist-mode grouping. |
| 2026-07-01 | `9ed36a98` | Clamp badge-size slider to Own mode's real range, fix combined resize tearing. |
| 2026-07-01 | `f9d9885d` | Coalesce same-tick minimalist updates into one resize. |
| 2026-07-01 | `297cbf65` | Consume per-platform+session gate and context files from state.d/. |
| 2026-07-01 | `7138a990` | Rebuild minimalist panel as two independent windows. |
| 2026-07-01 | `4557ad55` | Persist combined-minimalist dismiss; drop redundant bubble chip. |
| 2026-07-01 | `e3bb8879` | Re-privatize AttentionBubbleView after minimalist rewrite. |
| 2026-07-01 | `01f34adc` | Squashed '.son-of-anton/' changes from 75827bd3..7ff652b2. |
| 2026-07-01 | `7efbaea5` | Merge SoA subtree squash commit. |
| 2026-07-01 | `c52a5bb0` | Write active-session.json to canonical main-worktree root. |
| 2026-07-01 | `8f74fc4e` | Bump hook binary version to 1.0.1. |
| 2026-07-01 | `654239e0` | Key Update-hooks banner on registration fingerprint, not version. |
| 2026-07-01 | `a8534a88` | Record codogotchi-27 (P8 lockstep version-proxy conflation). |
| 2026-07-01 | `32a2a737` | Add right-click "Hide panel" affordance to Minimalist badge. |
| 2026-07-01 | `9a759b5b` | Add right-click "Force Idle" escape hatch + prune stale slices. |
| 2026-07-01 | `3bb08ccd` | Stop RPG HUD from chasing the pet mid-drag. |
| 2026-07-01 | `9695334d` | Polish menu-bar dropdown + fix Customization tab layout. |

---

## This session: closing the gate-badge gap (pre-Phase-15)

Investigating ahead of Phase 15 planning ("pet per active agent thread") surfaced that the two Phase 14-retrospective deferrals above were only *half* resolved by `297cbf65`: son-of-anton was already writing per-origin `<origin>:<session_id>.gate.json`/`.context.json` files, and `LivePollingDriver` had started reading them — but only the single globally-newest file across every platform, and the result was never wired to any window. Concretely, before this session:

- `LivePollingDriver.applyGateBadge` was never assigned in `MenubarApp.swift` — dead sink.
- `FloatingPetWindowPool.update()` never called `applyGateBadge` on any window (own, combined, or minimalist) — the sink existed on the protocol but nothing invoked it.
- `MinimalistWindowController.applyGateBadge` was an explicit no-op, and `MinimalistPanelManaging` had no gate-badge method at all.
- With two platforms concurrently mid-delivery, whichever platform's gate file happened to be most-recently-written on disk would win globally — there was no per-platform routing.

Direct-to-main changes made in this session (self-reviewed via `/code-review`, not routed through SoA tickets — see the developer's explicit approval for this specific change; standard practice returns to SoA phase delivery starting with Phase 15):

- **`GateJsonReader.swift`** — added `PerPlatformGateReader`, scanning `state.d/` for `<origin>:<session_id>.gate.json`/`.context.json`, keyed by origin (mirrors `StateJsonReader.readPerPlatformDirectory`'s shape).
- **`LivePollingDriver.swift`** — each poll tick now merges every active origin's *own* gate into its *own* activity state (so the 30s gate animation plays on the platform that actually drove it, not just the legacy single-window status item) and resolves each origin's persistent ticket/gate badge independently. Falls back to the legacy flat `gate.json`/`delivery-context.json` only when exactly one origin is active, to avoid misattributing a pre-Phase-17 hook's unattributed gate to the wrong platform when several are active.
- **`PerPlatformSnapshot.swift`** — gained a `gateBadges: [String: GateBadgeContent]` field alongside `perPlatform`.
- **`FloatingPetWindowPool.swift`** — now calls `applyGateBadge` per window every tick: each Own/Minimalist window gets its own origin's badge; the Combined window's badge follows whichever origin is currently winning the shared pet (same precedent as its existing platform-chip logic).
- **`FloatingPetController.swift` / `FloatingPetPanel.swift`** — `MinimalistPanelManaging` gained `applyGateBadge(content:)`; `MinimalistPanelController` now hosts a `GateBadgePanel` (the same view Own mode uses — `GateBadgeView`/`GateBadgeLayout` reused verbatim, ticket token stacked over gate token) positioned centered above the badge strip's platform-chip + animation-badge, scaling with the same user-controlled badge-size slider.
- **`DeveloperTabViewModel.swift` / `SettingsWindowController.swift`** — the Developer tab's gate/context diagnostic dump now shows the newest per-origin `state.d/` slice when one exists (labeling the section with the actual filename, e.g. `claude_code:sess.gate.json`), falling back to the legacy flat files — closing a gap the developer spotted live in the Settings UI while this work was in flight (it was still showing only the legacy files).
- Added regression coverage: two new `LivePollingTests` (concurrent multi-origin gate/badge routing, and the single-origin legacy fallback), four new `FloatingPetWindowPoolTests` (own-mode routing, badge-clear-on-disappear, combined-mode winner-follows, minimalist routing), and two new `DeveloperTabViewModelTests`. Full suite: 703 tests, 0 failures.

**Known accepted trade-off (not fixed in this pass):** each poll tick now performs three separate directory listings of `state.d/` (the pre-existing `readPerPlatformDirectory` and `decide()`'s legacy `newestFile` scan, plus this session's new `PerPlatformGateReader.read`). Consolidating into one shared listing is a reasonable future cleanup but was judged out of scope for this fix — see the self-review finding recorded for this diff.

**Remaining gap for Phase 15 to pick up:** the animation-state and badge merge above is per-*origin*, not per-*session* — a platform driving two concurrent sessions (the literal Phase 15 scope, "pet per active agent thread") will still collapse to one merged state per origin, same as `readPerPlatformDirectory` does for the base activity state today.

## Addendum (2026-07-01): Settings window gains Dock/Cmd+Tab presence while open

Small direct-to-main follow-up requested after this ledger was first committed, same "narrow, developer-approved fix" exception as the gate-badge work above — not routed through SoA tickets.

Codogotchi runs as an `LSUIElement` (`.accessory`) menu-bar agent, so its Settings window previously had no Dock icon and no Cmd+Tab entry — easy to lose track of behind other windows. Mirrors Tailscale's own Settings window behavior:

- **`SettingsWindowController.swift`** — `show(tab:)` now calls `NSApp.setActivationPolicy(.regular)` before creating or resurfacing the window; `windowWillClose` reverts to `.accessory`. No other window (onboarding, floating pet panels) needs `.regular`, so the revert is always clean.
- **Regression coverage:** `testSettingsWindowTogglesActivationPolicy` in `SettingsWindowOpenTests.swift` asserts the `.accessory → .regular → .accessory` round trip directly against `NSApp.activationPolicy()`.
- Verified manually by the developer in the running app; the assistant's own GUI-automation verification attempt was inconclusive (see below) and unit tests were used as the substitute check.

**Incident note:** while verifying this change, an assistant-run `pkill -f "Codogotchi.app/Contents/MacOS/Codogotchi"` matched both the debug build under DerivedData and the developer's live installed app at `/Applications/Codogotchi.app`, killing the running production instance. It auto-relaunched and returned to a healthy `.accessory` state, but the pattern was too broad — should have scoped to the DerivedData path only. Flagging here so the habit doesn't repeat: prefer `pkill -f <derived-data-path>` or matching by PID over a substring that also matches `/Applications`.

## Follow-up recommendations

1. **This file is the closeout ledger for the Phase-14→Phase-15 mainline window.** New work resumes under structured SoA phase/ticket delivery for Phase 15.
2. Phase 15 ("pet per active agent thread") should build on `PerPlatformGateReader`/`resolvePerPlatform` rather than re-deriving per-origin gate routing — extending both to key by `origin:session_id` instead of `origin` alone is the natural next step once per-session windows exist.
3. Consider folding the three per-tick `state.d/` directory scans noted above into a single shared listing as part of Phase 15's state-reading changes, since that phase is already touching this exact code path.
4. Hold the direct-to-main exception to genuinely narrow fixes going forward; this session's change was reviewed as one because its 4-part scope was named and developer-approved up front (self-review substituting for ticket review, explicitly), not because it should set precedent for skipping SoA delivery on future multi-file changes.

## Suggested commit subject

`docs: capture post-phase-14 mainline sweep and Phase 15 gate-badge prep`
