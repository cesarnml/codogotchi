# Window Capability Matrix — Own / Minimalist / Combined

Status: **Approved.** Developer-dispositioned 2026-07-12 (row-by-row disposition stop per `docs/product/delivery/phase-17/ticket-01-capability-matrix.md`).

## Purpose

This matrix is the durable contract for Phase 17 (Surface Convergence) and beyond. It enumerates every affordance the code currently exposes for the three window shapes and names every cross-shape difference as either:

- `intentional` — a deliberate capability distinction, to be reproduced verbatim by the converged renderer/coordinator/router, never converged away.
- `bug` — unintentional drift, to be restored as a **separate commit** inside the convergence ticket that owns the affected surface, each with a review-gap ledger entry (per `docs/product/delivery/phase-17/implementation-plan.md`, Review Rules).

## Amendment rule

Mid-phase changes to this matrix (missed affordances discovered during P17.02–P17.06) require developer sign-off before this file changes. The amending commit cites that sign-off explicitly.

## Shape definitions

- **Own** — `PlatformMode.own`. Rendered by `FloatingPetController` + `FloatingPetPanelController` + `FloatingPetInteractionView`, conforming to `FloatingPetPanelManaging`.
- **Minimalist** — `PlatformMode.minimalist`. Rendered by `MinimalistWindowController` + `MinimalistPanelController` + `MinimalistBadgeView`, conforming to `MinimalistPanelManaging`.
- **Combined** — `WindowKey.combined`. **Not a third renderer.** It is a shared render slot that all `.combined`-mode platform origins fold into. It routes through the Own factory when `combinedMinimalistEnabled == false` (default) or the Minimalist factory when the user has toggled combined-minimalist on (`FloatingPetWindowPool.swift:834-849`). Rows below therefore mostly read as "Combined = whichever of Own/Minimalist it's currently routed through," except where `.combined` is explicitly special-cased in code (flagged per row).

---

## 1. Prompt items / hide-prompt behavior

Source: `FloatingPetInteractionView.presentHidePrompt` (Own), `MinimalistBadgeView.presentHidePrompt` (Minimalist), `FloatingPetHidePrompt.swift`, `MinimalistPanelSizePill.swift`.

| # | Capability | Own | Minimalist | Combined | proposed | disposition |
|---|---|---|---|---|---|---|
| R1.1 | Trigger for hide-prompt | Right-click, gated to inside pet bounds + no active drag/resize (`FloatingPetHidePrompt.shouldPresent`) | Right-click anywhere on the strip, no bounds gate | Inherits routed shape's trigger | intentional | intentional |
| R1.2 | Force Idle item | Present when `state != .idle`, cached bool kept in sync on `apply(state:)` | Present when `state != .idle`, computed live at present-time | Inherits routed shape | intentional (same predicate, different caching mechanism — not a behavior difference) | intentional |
| R1.3 | Rename… item | Present whenever `currentSessionLabel != nil` (session-keyed, plain-origin, and combined windows all offer it) | Same gate | Same gate | intentional | intentional |
| R1.4 | Sync Label item | Session-keyed only (`hasActiveSessionBadge`) | Session-keyed only (`currentSessionNumber != nil`) | Never offered for combined/plain-origin (no session id) | intentional | intentional |
| R1.5 | Prune Session item | Session-keyed only, same gate as Sync Label; confirmation alert unless `skip_prune_confirmation` feature flag set | Same | Never offered for combined/plain-origin | intentional | intentional |
| R1.6 | Mode-switch item | "Minimalist Mode" — unconditional | "Pet Mode" — unconditional (inverse target) | Routes through whichever shape combined is currently rendered as | intentional | intentional |
| R1.7 | Panel Size… item | **Absent** — no size concept, panel is freely resizable by drag | **Present**, unconditional — opens `MinimalistPanelSizePillPanel` | Present only when combined is routed to Minimalist | intentional (Own has no analogous size concept) | intentional |
| R1.8 | Hide All Other Pets item | Unconditional, identical | Unconditional, identical | Same | intentional (no difference) | intentional |
| R1.9 | Hide-this item | "Hide pet", always last | "Hide panel", always last (same semantics, different title) | Inherits routed shape's title | intentional (cosmetic title only) | intentional |
| R1.10 | Mode-switch pill target for `.combined` | N/A | N/A | Routes to `customizationStore.setCombinedMinimalistEnabled(_:)` — a separate boolean, **not** the per-origin `platform_modes` map every other window key uses (`FloatingPetWindowPool.modeSwitchOrigin` returns `nil` for `.combined`) | intentional (there is no single origin to flip for a folded window — this is the necessary combined-specific branch) | intentional |
| R1.11 | Hide-prompt dismiss on window resign-key | Listens for `NSWindow.didResignKeyNotification` on its own panel (`FloatingPetInteractionView.installHidePromptDismissObservers`) | **No equivalent observer** — only app-resign-active + mouse/keyboard monitors | Inherits routed shape | dead code, not a behavioral gap | intentional |
| R1.12 | Hide-prompt dismiss on app resign-active, global mouse-down, global keyboard, prompt coordinator singleton | Present, identical implementation | Present, identical implementation | Same | intentional (byte-for-byte shared mechanism) | intentional |

**Note on R1.11 (developer-confirmed):** Both panels are `.nonactivatingPanel` borderless panels that can never become key, so Own's extra `didResignKeyNotification` observer never fires. Dispositioned `intentional` — harmless dead code, not carried into the converged prompt component.

### `MinimalistPanelSizePill` (Minimalist-only, no Own analog)

| # | Capability | Own | Minimalist | Combined | proposed | disposition |
|---|---|---|---|---|---|---|
| R1.13 | Panel size pill exists at all | Absent | Present | Present only when combined routes to Minimalist | intentional | intentional |
| R1.14 | Panel size pill scope | N/A | Drives the **global** `minimalist_badge_scale` setting — affects every Minimalist strip on screen, not just the one clicked; only the clicked strip live-applies immediately, siblings pick it up next poll tick | Same as Minimalist when routed there | intentional | intentional |
| R1.15 | Panel size pill window level | N/A | `.popUpMenu` (higher than the `.floating` level used by all other chrome), explicitly to avoid being buried by poll-tick chrome re-fronting | N/A | intentional (documented workaround in code comment) | intentional |

---

## 2. Panel-managing protocols

Source: `FloatingPetController.swift` (`FloatingPetPanelManaging` lines 71-115, `MinimalistPanelManaging` lines 302-332).

| # | Capability | Own | Minimalist | Combined | proposed | disposition |
|---|---|---|---|---|---|---|
| R2.1 | Protocol conformance | `FloatingPetPanelManaging` via `FloatingPetPanelController`, wrapped by `FloatingPetController` | `MinimalistPanelManaging` via `MinimalistPanelController`, wrapped by `MinimalistWindowController` | Inherits routed shape's protocol — no `WindowKey`-level branching inside either protocol or its conformers | intentional | intentional |
| R2.2 | `apply(state:visualMode:)` (sprite-scene state) | Present | **Absent from protocol** — no sprite scene concept | Present only when routed to Own | intentional | intentional |
| R2.3 | `applyRPGState` / `setRPGHUDEnabled` / `setHUDDemoActive` / `setHUDPinned` | Present, full RPG HUD lifecycle | **Absent from protocol.** `MinimalistWindowController.applyRPGState` is an explicit no-op with comment "Minimalist mode intentionally has no sprite and no RPG HUD" | Present only when routed to Own | intentional (explicitly documented in code) | intentional |
| R2.4 | `setInteraction` (drag-interaction state) | Present | Absent from protocol | Present only when routed to Own | intentional | intentional |
| R2.5 | `replacePets` (pet-asset reassignment) | Present, visually swaps sprite | `MinimalistWindowController.replacePets` is an unconditional no-op — a strip has no sprite to swap | Present (visual) only when routed to Own | intentional | intentional |

---

## 3. Chrome panels: anchoring, drag, fronting

Source: `AnimationBadgePanel.swift`, `GateBadgePanel.swift`, `AttentionBubblePanel.swift`, `SpeechBubblePanel.swift` (conflict bubble), `RPGHUDPanel.swift`, hosted from `FloatingPetPanelController.swift` (Own) and `MinimalistPanelController.swift` (Minimalist).

| # | Capability | Own | Minimalist | Combined | proposed | disposition |
|---|---|---|---|---|---|---|
| R3.1 | AnimationBadge structure | **Separate floating `NSPanel`** (`level = .floating`), anchored bottom-left around the pet frame via `AnimationBadgeLayout` | **Embedded subview** inside `MinimalistBadgeView`'s own content view — not a separate panel | Inherits routed shape's structure | intentional (documented in `MinimalistPanelController` comment as avoiding a "shape-shifted panel" bug class) | intentional |
| R3.2 | AnimationBadge drag routing | `onDragBegan/Changed/Ended` → `beginChromeDrag`/`continueChromeDrag`/`endChromeDrag` → moves the pet panel | Drag lands directly on `MinimalistBadgeView` itself (`mouseDown/mouseDragged`) since it's embedded, moving the strip | Inherits routed shape | intentional (same end effect — dragging chrome moves the panel — different plumbing because of R3.1) | intentional |
| R3.3 | AnimationBadge right-click | `onRightClickRequested` → `presentChromeHidePrompt` → same prompt as clicking the sprite | Embedded in strip's own `rightMouseDown` handling | Inherits routed shape | intentional | intentional |
| R3.4 | GateBadge structure & anchoring | Separate floating panel, lazily created on first non-nil gate content, centered above the pet via `chipLeadingX` | Separate floating panel, lazily created, stacked above the strip centered on its midX | Inherits routed shape's anchor geometry | intentional (both are separate panels; anchor point differs because the host geometry differs) | intentional |
| R3.5 | GateBadge drag/right-click | Routes into pet panel's own drag/prompt | Routes into `badgeView.beginExternalDrag()` / `presentHidePrompt(anchorInScreen:)` — the strip's equivalent | Inherits routed shape | intentional | intentional |
| R3.6 | AttentionBubble drag | Not draggable — no drag handlers on this panel type | Not draggable — same | Same | intentional (identical, no divergence) | intentional |
| R3.7 | AttentionBubble anchor | Anchored via animation-badge panel's own frame (`chipLeadingX`/`chromeBottomY`) | Anchored to `badgeFrame.minX + hPad` / `badgeFrame.minY` | Inherits routed shape | intentional (cosmetic geometry difference only, behavior identical: Dismiss + Focus actions, re-fronted only while `attentionActive`) | intentional |
| R3.8 | SpeechBubble (conflict bubble) structure & behavior | Lazily created, positioned `aboveFloatingPetFrame:`, no drag, `onAction` opens Settings, `onDismiss` | Lazily created, positioned `aboveMinimalistStrip:`, no drag, same action/dismiss contract | Inherits routed shape | intentional (geometry differs, behavior identical) | intentional |
| R3.9 | RPG HUD / Tombstone / Regen Meter panels | **Present.** Full hover-driven reveal/fade lifecycle, transient flash-reveal on heart/level events, drag-suppression during pet drags | **Absent entirely.** No fields for these panels exist on `MinimalistPanelController`; confirmed by R2.3's no-op | Present only when routed to Own | intentional (explicitly documented) | intentional |
| R3.10 | Chrome fronting cadence | `orderFrontRegardless()` on every poll-tick reposition (not one-time) | Same | Same | intentional (identical mechanism both shapes) | intentional |

---

## 4. Session badge / label / tooltip

Source: `PlatformSessionBadge.swift` (shared component, no per-shape subclassing), resolution in `FloatingPetWindowPool.swift:1139-1191`.

| # | Capability | Own | Minimalist | Combined | proposed | disposition |
|---|---|---|---|---|---|---|
| R4.1 | Badge component | `PlatformSessionBadge`, embedded beneath `AnimationBadgePanel`'s stack | Same `PlatformSessionBadge`, embedded in `MinimalistBadgeView.outerStack` beneath chip+pill row | Inherits routed shape's embedding point | intentional (same component, different host) | intentional |
| R4.2 | Label content & precedence | User rename → retrieved platform title → "Session N" → platform display name, via `sessionDisplayLabel(forWindowKey:)` | Identical precedence, same function | Same | intentional (shared resolver, no divergence) | intentional |
| R4.3 | Tooltip content | `sessionPromptSummary(forWindowKey:)`, `nil` for non-session-keyed windows | Same | Same | intentional (no divergence) | intentional |
| R4.4 | Panel resize on session-row appearance | Fixed/user-resizable frame; session badge row fits within existing space, no self-resize | Panel height grows by `Layout.sessionRowExtraHeight` (26pt) when a session number is assigned — strip is content-tight and must resize | Inherits routed shape | intentional (resizing-mechanics difference driven by each shape's own layout model, not a content/affordance difference) | intentional |

---

## 5. Rename semantics

Source: `SessionLabelStore.swift`, wiring in `MenubarApp.swift:313-320` (Own) / `:392-398` (Minimalist), resolution in `FloatingPetWindowPool.swift:1148-1184`.

| # | Capability | Own | Minimalist | Combined | proposed | disposition |
|---|---|---|---|---|---|---|
| R5.1 | Rename trigger & UI | Right-click → "Rename…" → `NSAlert` text-entry modal, byte-identical logic to Minimalist | Right-click → "Rename…" → `NSAlert` text-entry modal, byte-identical logic to Own | Inherits routed shape | intentional (no divergence) | intentional |
| R5.2 | Rename storage key | `SessionLabelStore` is a flat `[WindowKey.rawValue: String]` dict — no shape-specific schema | Same | Same store, same schema | intentional (single shared store) | intentional |
| R5.3 | Session-keyed rename scope | Per-session (`"origin:session_id"` key) | Same | Session-keyed combined windows use same scoping | intentional | intentional |
| R5.4 | Plain-origin rename scope | Keyed by bare origin string — effectively global to that platform since only one window exists for that origin in this state | Same | N/A (combined uses its own key, see R5.5) | intentional | intentional |
| R5.5 | Combined rename scope | N/A | N/A | Keyed by the literal string `"combined"` — **confirmed globally-scoped by construction**: every origin currently in `.combined` mode shares this one `WindowKey`, so a rename here persists regardless of which platform is currently "winning" the shared pet | **intentional — pre-seeded confirmed design** per phase implementation plan | intentional |

*(R5.5 is pre-dispositioned per the ticket's explicit instruction: "Combined/plain-origin rename semantics = confirmed design (intentional)." Verified directly against `SessionLabelStore`'s single flat keyspace in this archaeology pass — no further developer input needed on this row.)*

---

## 6. `MenubarApp` factory closures

Source: `MenubarApp.swift` — `windowFactory` (Own, lines 218-383) and `minimalistWindowFactory` (Minimalist, lines 384-519). Both are called for every `WindowKey` shape including `.combined`; there is no third "combined factory."

| # | Capability | Own | Minimalist | Combined | proposed | disposition |
|---|---|---|---|---|---|---|
| R6.1 | Duplicated closure wiring (`onRenameRequested`, `onSyncLabelRequested`, `onHideAllOtherPetsRequested`, `onAttentionDismissed`, `onForceIdle`, hide-this-window, mode-switch) | ~90% line-for-line duplicated logic across the two factories, same comments reworded per panel type | Same | N/A (factory selection concern, not a shape-behavior row) | intentional (near-term structural debt, already tracked by ticket P17.05 "Seam-2 router + factory collapse" as the planned fix — not fresh drift to restore here) | intentional |
| R6.2 | Pet-asset resolution | Resolves sprite assets via `petAssetResolver.resolve(petId:)` | No pet-asset concept in this factory at all | Present only when routed to Own | intentional | intentional |
| R6.3 | `onPanelSizeChanged` wiring | Absent | Present — drives `minimalist_badge_scale` | Present only when routed to Minimalist | intentional | intentional |
| R6.4 | Idle escalation config | `idleEscalationConfig`/`initialIdleAge` passed into `FloatingPetPanelController` init (scene-level idle escalation) | No analog on `MinimalistPanelController` init | Present only when routed to Own | intentional | intentional |

---

## Restoration ledger

Rows dispositioned `bug` above are restored as separate commits inside the convergence ticket that owns the affected surface (per phase Review Rules), each with a review-gap ledger entry.

**No rows were dispositioned `bug`.** All 33 cross-shape difference rows were dispositioned `intentional` (including R1.11, confirmed dead code rather than a behavioral gap, and R5.5, pre-seeded confirmed design). This ledger stays empty unless a future matrix amendment introduces a `bug` disposition.

| Row | Surface | Owning ticket | Ledger entry |
|---|---|---|---|
| — | — | — | — |
