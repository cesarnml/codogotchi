# Phase 19 — Fold-Window Session Identity

> Every floating pet window carries its real backing `state.d` session identity as data, so Prune stops silently no-op'ing on folded/non-multiplexed windows, and the window's label live-tracks the real session it's showing instead of a static fold-global string.

## Epic

None — standalone phase. Direct architectural sequel to Phase 18 (Pool/Derive/Diff/Apply refactor), which correctly computes a fold's winning session every tick but never threads that identity past the display payload.

## Product contract

Today, right-clicking Prune on a Combined or session-pets-off (origin-folded) window does nothing — the menu item isn't even offered, because `FloatingPetPromptCapabilities.hasActiveSession` and `FloatingPetWindowPool.pruneSession` both gate on `WindowKey.sessionIdentity`, which is `nil` for every window except `.session`-keyed ones. The window's label is also a static, manually-set fold-global string, not the real session's own LLM-assigned, platform-synced label.

When this phase is complete: a user can Prune ANY rendered floating pet window — solo platform, origin-folded, or Combined — and it removes the correct, currently-displayed session's `state.d` slice. Every window's primary label reflects the real winning session's own live label. Origin-folded (when folding more than one real session) and Combined windows additionally show a small, fixed, non-renamable badge signaling "this window isn't showing itself, it's showing something else" — visible exactly when the window's own identity and its resolved session identity diverge.

## Grill-Me decisions locked

- **Identity carrier:** a new additive field on `DesiredWindow`, not a change to `WindowKey`'s enum shape — `WindowKey.rawValue` has a narrow, deliberately-protected serialization contract (`app-state.json`/`session-labels.json`/slice filenames) that must not be touched.
- **Data source:** `PoolDerive` already computes the real winning session's `WindowKey` every tick (`combinedWinner`/`winnerEntry` locals) for `.combined` and non-combined folds alike — this phase persists that value onto `DesiredWindow` and reuses it, it does not compute anything new.
- **Label resolution:** reuse the *existing* per-session label path (`PoolTickInput.sessionLabels`/`knownSessionTitles`, already populated per real render key today) keyed by the resolved identity, instead of the fold key. No new label-fetching mechanism.
- **`"default"`-sentinel slices are in scope:** a solo, non-multiplexed origin's single slice (`sessionId == "default"`, mapped to `WindowKey.origin`) gets the identical fix — Prune must work there too, not just for genuinely folded multi-session windows.
- **Mode badge visibility rule:** shows exactly when `resolvedIdentity != key` — not a session-count special case. A solo `.origin` window (nothing folded) never shows it; `.combined` always shows it; a multi-session `.origin` fold shows it only while actually folding more than one session.
- **Manual rename stays available**, unchanged in kind, as an override on the new live-resolved label — deprioritized as a design focus since platform-synced auto-labeling is the expected default for most users.
- **Sticky fold-global rename storage becomes obsolete** once this ships — active cleanup vs. leaving it inert is left to ticket-level judgment during P19.01/P19.04, not a blocking product decision.
- **Ticket sequencing:** P19.01 (identity + label) is the foundation everything else reads from; P19.02+P19.03 (Prune functionality — the actual user-facing bug) land next as the payoff; P19.04 (badge) is purely additive polish and goes last since nothing else depends on it.

## Ticket Order

1. `P19.01 Resolve real session identity, reuse it for the live label`
2. `P19.02 Prune works for every window kind`
3. `P19.03 Prune confirmation and menu text name the real session`
4. `P19.04 Mode-indicator badge`

## Ticket Files

- `ticket-01-resolve-session-identity-live-label.md`
- `ticket-02-prune-every-window-kind.md`
- `ticket-03-prune-menu-names-real-session.md`
- `ticket-04-mode-indicator-badge.md`

## Exit Condition

A user can right-click Prune on any floating pet window — solo platform, origin-folded, or Combined — and it removes the correct, currently-visible session's `state.d` slice every time, with no silent no-ops. Every window's primary label reflects the real winning session's own LLM-assigned, platform-synced identity, live-updating if the winner rotates. Fold windows (origin-folded with 2+ real sessions, or Combined) show a small fixed badge naming their mode, and their Prune menu item names the specific session about to be removed before the user commits. Manual rename still works as an override. Non-winning folded sessions remain visible only via Settings > Sessions; winner-election behavior and the Sessions tab are unchanged.

## CI Baseline

`bun run ci:quiet` on `v3_preview` at commit `c2fa36c4` (phase-18 advisory-observation triage, latest commit before phase-19 starts): **pass** — biome verify clean, `bun test` clean, mac test suite 1146 tests / 3 skipped / 0 failures.

> Baseline recorded: 2026-07-14 — pass, 1146 mac tests green, no pre-existing failures to account for.

## Review Rules

- Tickets must be merged in order (P19.01 → P19.02 → P19.03 → P19.04) — each depends on identity resolution or menu-item existence established by the previous one.
- Each ticket PR must pass CI before the next ticket starts.
- No pre-existing CI failures to carry forward per the baseline above; any new failure blocks the ticket that introduced it.
- `subagentReview: skip_doc_only`, `ticketBoundaryMode: gated`, `prReview: disabled`, matching Phase 18's run policy.

## Explicit Deferrals

- Surfacing every folded-away, non-winning session inside the floating-window UI — Settings > Sessions remains the only place for that; no ticket in this phase touches it.
- Settings > Sessions tab and `SessionsTabViewModel`/`SessionLabelStore`'s disk-scan logic — untouched.
- Combined-mode winner-election algorithm (freshest-entry, tie-breaking, transient-gap retention) — Phase 18 already correct; this phase only reuses the winner it already computes.
- `state.d` file-format or schema changes — none needed.
- Active migration/purge of obsolete fold-global `SessionLabelStore` entries — left inert unless a ticket's implementer judges cleanup trivial in-scope; not a blocking requirement.

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- If `PoolTickInput.sessionLabels`/`knownSessionTitles` turn out NOT to already contain entries for every raw per-slice `WindowKey` when session-pets is off (contradicting the Grill-Me decision that data plumbing already exists) — surface as a scope-expanding discovery in P19.01 rather than silently reworking `LivePollingDriver`.

## Phase Closeout

Retrospective: required
Why: Direct architectural sequel to a Phase 18 gap (session identity computed but not threaded to downstream per-window actions); establishes a durable, reusable click-time identity-resolution pattern future fold-window features will build on. This phase also reopens the v3 feature freeze as a deliberate, named exception (see `project_v3_scope` memory) — worth documenting why.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-19-fold-window-session-identity-retrospective.md`
