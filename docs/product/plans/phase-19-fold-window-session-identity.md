# Phase 19: Fold-Window Session Identity

**Delivery status:** Product plan approved — awaiting decomposition (`/soa decompose`).

## TL;DR

**Goal:** Every floating pet window — whatever `WindowKey` case renders it (`.session`, `.origin`, `.combined`) — carries its real backing `state.d` session identity as first-class data, so per-window actions (starting with Prune) never silently no-op just because the window happens to be showing a folded or non-multiplexed view.

**Ships:**
- `DesiredWindow` for a `.origin`/`.combined` key carries the currently-winning session's real backing identity (a genuine session id, or the `"default"` sentinel for a non-multiplexed origin) as data, resolved fresh every tick.
- Prune resolves and acts on that real identity for every window kind — `.session`, `.origin` (folded or singular), and `.combined` — instead of silently no-op'ing whenever `WindowKey.sessionIdentity` is `nil`.
- Every window's primary label becomes the real winning session's label — LLM-assigned and kept in sync with the underlying AI-agent platform's own session title, via the same resolution path `.session`-keyed windows already use (`sessionLabels`/`knownSessionTitles`, with manual rename still available as an override, deprioritized as a design focus since auto-sync is the high-ROI default). The label now live-tracks whichever session currently wins the fold, replacing the prior fold-global sticky label.
- Origin-folded and Combined windows additionally gain a small, non-renamable mode-indicator badge (platform name, or "Combined") shown alongside the primary label — a fixed visual cue distinguishing "this window is folding something" from a genuinely single-session window. `.session`-keyed windows don't need it; they're inherently unambiguous.
- The Prune context-menu item on a fold window (origin-folded or Combined) surfaces the resolved session's identity in its label, so the user knows what they're about to prune before committing — reinforced by the same live label now being visible on the window itself.

**Defers:**
- Surfacing every folded-away, *non-winning* session inside the floating-window UI (submenus, per-session rows, etc.) — Settings > Sessions remains the only place to see and act on sessions that aren't currently winning a fold. This phase makes the *winner's* identity live and visible; it does not expose the siblings underneath.
- Settings > Sessions tab itself — its per-slice scan-based identity resolution is already correct and isn't touched.
- Combined-mode winner-election algorithm (freshest-entry selection, tie-breaking, transient-gap retention) — Phase 18 already got this right; this phase only threads the *winner's identity* further downstream, it never changes who wins.
- Any `state.d` file-format or schema change — this phase resolves identity that already exists on disk; it adds no new persistence.
- Migration/cleanup of the old fold-global sticky-rename entries in `SessionLabelStore` (keyed by raw `"combined"`/origin strings) — decompose-time decision on whether to actively purge them or let them become inert, unread dead data once the new per-session-resolved label path replaces the old lookup.

---

Every `state.d/` slice's filename already encodes its real backing identity — an `(origin, sessionId)` pair, where `sessionId` is either a genuine session id or the `"default"` sentinel for an origin with no session multiplexing. Phase 18's `PoolDerive` fold logic (`.origin`/`.combined` `WindowKey` cases) correctly picks a winning session's `state.d` slice to render every tick, but only threads that winner's identity as far as the display payload needs it (activity state, and a fold-global sticky label fallback) — it never survives into the window's addressable identity, and the visible label doesn't track it either. The result is two compounding problems: `FloatingPetWindowPool.pruneSession` requires `WindowKey.sessionIdentity`, which only the `.session` case provides, so Prune silently does nothing on any folded or non-multiplexed window — the single most common configuration for a user with combined-mode or session-pets-off origins; and the label a user sees on that window is a static, manually-set fold-global string rather than the real session's own LLM-assigned, platform-synced label, so there's no live signal when the underlying winner rotates. This was found live, dogfooding Phase 18's shadow-tick soak, and traces to an architectural gap rather than an implementation bug in any one ticket: session identity is discarded a step too early for downstream per-window actions and display to reach it.

## Phase Goal

This phase should leave the product in a state where:

- Right-clicking Prune on ANY rendered floating pet window — regardless of whether it's `.session`, `.origin`, or `.combined` keyed, and regardless of whether the underlying slice is genuinely session-multiplexed or uses the `"default"` sentinel — removes the correct, currently-displayed `state.d` slice.
- Every rendered window's primary label is the real winning session's LLM-assigned, platform-synced label — live, tracking whichever session currently wins the fold — with manual rename still available as an override, same as `.session`-keyed windows support today.
- An origin-folded or Combined window additionally shows a small, non-renamable badge naming its mode (platform name, or "Combined"), so it's visually distinguishable from a genuinely single-session window at a glance.
- A fold window's Prune menu item names the specific session it is about to remove, resolved fresh at click-time against that tick's actual winner (never a stale or rotated-out identity) — reinforced by the same identity already being visible as the window's live label.
- No change to the Combined-mode winner-election algorithm or to Settings > Sessions — this phase changes what a fold window displays and what Prune can act on, nothing about who wins a fold or how non-winning sessions are managed elsewhere.

## Committed Scope

### Identity resolution through the derive/apply pipeline

- `PoolDerive`'s per-tick fold (`.origin`, `.combined`) carries the winning entry's real backing identity (session id or `"default"` sentinel) into that tick's `DesiredWindow`, in addition to whatever it already resolves for display.
- The identity resolved is always the *current* tick's winner — no caching across ticks that could go stale if the winner rotates between render and click.

### Prune, for every window kind

- `FloatingPetWindowPool.pruneSession`'s entry condition is extended so it no longer requires `WindowKey.sessionIdentity` specifically — it resolves and prunes the real backing identity for `.origin` (folded or singular) and `.combined` windows too, using the same identity threaded through above.
- The `"default"`-sentinel case (a genuinely non-multiplexed origin's single slice) is pruned the same way a real session is — same code path, no special-cased no-op.

### Live, synced primary label for every window

- The primary label shown on an `.origin`/`.combined` window switches from the static fold-global sticky string to the same resolution path `.session`-keyed windows already use: LLM-assigned, synced to the underlying AI-agent platform's own session title (`sessionLabels`/`knownSessionTitles`), resolved against the tick's real winner.
- Manual rename remains available as an override (existing mechanism, unchanged in kind) — deprioritized as a design focus for this phase since platform-synced auto-labeling is the expected high-ROI default for most users.

### Mode-indicator badge for fold windows

- An `.origin` (when folding more than a solo default slice) or `.combined` window gains a small, fixed, non-renamable badge naming its mode — platform name or "Combined" — shown alongside the live primary label, so folded windows stay visually distinguishable from genuinely single-session windows.

### Prune menu clarity for fold windows

- The Prune context-menu item on a fold window includes the resolved session's identity in its displayed text (e.g. platform + label/summary), reinforcing what's already visible as the window's live label, so a user acting on a folded window can see what they're about to remove without needing to check Settings > Sessions first.

## Explicit Deferrals

- **Non-winning folded-session visibility** — sessions folded underneath a Combined or origin window that are NOT currently winning stay invisible from the floating-window UI. Deferred because it's a materially larger UI-surface phase (submenu design, interaction model) than "make the winner's identity live and correct," and Settings > Sessions already covers this need today.
- **Settings > Sessions tab** — its disk-scan-based per-slice identity resolution already works correctly and independently of the fold/derive pipeline; not in scope.
- **Combined-mode winner-election logic** — Phase 18 shipped correct freshest-entry selection, deterministic tie-breaking, and transient-gap retention. This phase consumes that winner's identity; it does not change how the winner is chosen.
- **`state.d` schema/format changes** — none needed; every identity this phase resolves already exists on disk today.
- **Active cleanup of obsolete `SessionLabelStore` fold-global entries** — the old sticky-rename slots (keyed by raw `"combined"`/origin strings) stop being read once the new per-session-resolved label path lands; whether to actively purge them from disk or let them go inert is a decompose-time call, not a product-plan commitment.

## Exit Condition

A user can right-click any floating pet window — a solo non-multiplexed platform window, an origin-folded window with session-pets on, or a Combined window spanning several platforms — and choose Prune, and it removes the correct, currently-visible session's `state.d` slice every time, with no silent no-ops. Every window's primary label reflects the real winning session's own LLM-assigned, platform-synced identity, live-updating if the winner rotates; fold windows additionally show a small fixed badge naming their mode, and their Prune menu item names the session about to be removed before the user commits. Manual rename still works as an override, same as it does for session-keyed windows today. Non-winning folded sessions remain visible only via Settings > Sessions, and winner-election behavior is unchanged.

## Retrospective

`required` — this phase is a direct architectural sequel to a gap Phase 18 left behind (session identity computed but not threaded to downstream per-window actions), and it establishes a durable, reusable pattern (resolve-the-real-identity-behind-a-fold-window-at-click-time, safe against per-tick winner rotation) that future fold-window features will build on. Worth capturing while fresh rather than rediscovering the same gap-shape later.
