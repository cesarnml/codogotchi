# Phase 17 Exit Audit

Audit date: 2026-07-12

Audited branch: `agents/p17-06-closeout-exit-audit-dogfood-dmg-retrospective`

## 1. One prompt system — PASS

- `FloatingPetPromptDismissal` is the sole owner of the global/local mouse,
  keyboard, and resign-active dismissal observer stack.
- `FloatingPetPromptBuilder` is the sole production `[FloatingPetPromptItem]`
  builder. Own and Minimalist retain view-level `presentHidePrompt` entrypoints
  only to provide their different anchors and named capabilities, as P17.02
  explicitly requires; neither surface constructs items or owns observers.
- `FloatingInteractionTests` exercise the exact matrix-driven item order and
  titles for Own, Minimalist, Combined, and session-keyed capability variants.

## 2. One renderer protocol and action factory — PASS

- The retired `FloatingPetPanelManaging` and `MinimalistPanelManaging` names
  have zero app-target hits.
- Both skins conform to `PanelManaging` and `PanelActionHandling`.
- `MenubarApp.wirePanelActions` is the only assignment site for the nine shared
  action handlers. The factories pass only the mode-switch target and the
  controller identity needed to hide the current window. Minimalist's panel
  size slider remains the intentional R1.7-only capability.
- `WindowActionRouter` exclusively owns the session/combined/plain-origin
  targeting policy for attention dismissal and Force Idle, with focused tests.

## 3. One chrome coordinator — FAIL (phase stop condition)

- Own and Minimalist each construct `ChromeFlockCoordinator`, and panel-instance
  lifecycle plus drag/right-click routing are centralized there.
- The approved exit condition does not hold for anchoring/fronting. Both
  controllers still reach through `existing*Panel` accessors and directly call
  `reposition(...)` / `orderFrontRegardless()` in their live re-anchor and
  presentation paths. P17.03's Rationale explicitly retained those paths to
  preserve the front-on-content-change versus reposition-only-live-update
  distinction, even though its Outcome and Refactor sections required deleting
  every per-shape anchoring/fronting path.
- This is a code completeness defect, not an audit-wording issue. Per P17.06's
  stop rule, the phase cannot proceed to publication until the coordinator owns
  those mechanics or the approved phase contract is explicitly changed.

## 4. Capability matrix matches code — PASS

- `docs/contracts/window-capability-matrix.md` was checked row by row against
  the converged prompt, renderer, chrome, and factory surfaces.
- R2.1 and the matrix preamble now name `PanelManaging` and
  `PanelActionHandling`; the retired protocol references were stale audit text,
  not a new capability or behavior amendment.
- All prompt rows were dispositioned intentional in P17.01/P17.02. No Phase 17
  drift-restoration commit exists, so no Phase 17 restoration ledger entry is
  required.

## 5. Behavior bar — PASS

- `bun run verify:quiet`: pass.
- `bun run mac:build`: pass.
- `bun run ci:quiet`: pass; `CodogotchiTests.xctest` executed 1,074 tests with
  zero failures before the final documentation-only audit commit. The final
  publication gate is rerun after all audit/retrospective files are formatted.

## 6. Local dogfood — PASS for ticket completion

- Packaged with `scripts/package-dmg.sh`; staged bundle verification passed.
- Artifact: `builds/Codogotchi.dmg`.
- SHA-256: `a201eca1c89911088f15729f2a2ecf8045f4cf778cf1c55cb081fc64a6ac897d`.
- Installed to `/Applications/Codogotchi.app`, version 2.7.0 (build 12), and
  launched from that path. Process inspection confirmed the installed binary
  running; UI inspection confirmed the live Minimalist strip rendered.
- No version bump, GitHub release, or download-page change was made.

The longer Phase 18 transition soak is deliberately still open: before Phase
18 execution, the installed daily-driver build must explicitly exercise Own,
Minimalist, and Combined with no unexplained regression. That soak is not
claimed complete by this ticket.
