# P17.01 Capability matrix (drafted from code, developer-dispositioned)

Size: 3 points
Type: docs
Scope: contracts
Red: skip

## Outcome

- `docs/contracts/window-capability-matrix.md` exists and enumerates the current window-shape × affordance grid (Own / Minimalist / Combined) as read from the code — covering at minimum: prompt items (both `presentHidePrompt` builders and the mode-switch pill), dismissal behavior, chrome panels (AnimationBadge, GateBadge, AttentionBubble, SpeechBubble, RPGHUD) and their anchoring/drag/fronting behavior, session badge/label/tooltip affordances, and rename semantics.
- Every cross-shape difference appears as its own row, initially marked `proposed: bug | intentional`, and carries an explicit developer disposition (`bug` or `intentional`) in the committed version — no row remains `proposed`.
- Known traps are pre-seeded and dispositioned: Combined/plain-origin rename semantics = confirmed design (intentional); the Own/Minimalist parity seam rows are each explicitly dispositioned rather than blanket-labeled.
- The matrix records the amendment rule: mid-phase changes require developer sign-off cited in the amending commit.
- The branch touches only documentation — zero code changes.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Human review at the PR is the gate for doc changes.**

## Green

- Enumerate affordances from the code, not from memory: the two prompt builders (`FloatingPetInteractionView.presentHidePrompt`, `MinimalistBadgeView.presentHidePrompt`), `MinimalistPanelSizePill`, the two panel-managing protocols in `FloatingPetController.swift`, the chrome panel controllers, and the `MenubarApp` factory closures. Combined is a `WindowKey` case rendered through the floating-panel path — its rows must reflect what that path actually does for combined keys, not a copy of Own's rows.
- Mark every cross-shape difference `proposed: bug` or `proposed: intentional`. Default under uncertainty is `intentional, documented` — never `fix`.
- **Stop condition (mandatory):** present the drafted grid to the developer and collect a row-by-row disposition for every difference row before any commit of the final matrix. This is the orchestrator stopping point for this ticket.
- Commit the approved matrix to `docs/contracts/window-capability-matrix.md`.

## Refactor

- Not applicable — doc-only ticket. No opportunistic code cleanup.

## Review Focus

- Completeness: does the grid cover every affordance the code exposes per shape, or only the famous ones? Missing rows become silent drift later.
- No silent dispositions: every difference row shows an explicit developer decision; the uncertainty default was applied only with the row visible to the developer.
- The matrix names capabilities (e.g. "Panel Size — Minimalist only") rather than describing implementations, so P17.02–P17.05 can parameterize against it.
- Downstream tickets P17.02–P17.05 are blocked until this ticket merges; verify the disposition stop actually happened (recorded in the ticket Rationale).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a — doc-only.
Why this path: matrix-first is the product plan's binding order; the disposition stop keeps restoration commits gated on explicit developer decisions.
Alternative considered: drafting the matrix pre-execution alongside delivery docs — rejected because the archaeology is real tracked work and decompose sessions are a poor place for disposition-quality code reading.
Deferred: encoding non-prompt matrix rows as tests (doc + closeout audit only); any code change.
Contract note: —
