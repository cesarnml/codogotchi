# P17.05 Seam-2 router + factory collapse

Size: 5 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- A Seam-2 router type owns "which slices does this window's action touch": the session / combined / plain-origin targeting policy currently inline in `MenubarApp`'s factory closures (attention dismissal fan-out, Force Idle slice selection, prompt-timer resets, and the other `onX` handler bodies).
- The router has unit tests covering targeting per `WindowKey` shape: session-keyed targets exactly its own slice, combined resets exactly its combined origin set, plain-origin targets its origin's winner slice — the semantics documented in today's closure comments become executable.
- `MenubarApp`'s two factory closures collapse to one parameterized factory of dumb wiring: `panel.onX = { router.handle(.x, for: key) }`; no targeting policy remains in the factory.
- No parallel comment blocks survive in `MenubarApp` — the per-shape targeting prose moves to the router (once) or dies.
- Full existing suite green; this is the phase's single `MenubarApp` disruption.

## Red

- Write router targeting tests first: for each action × `WindowKey` shape, assert which slices/origins are touched (derived from the current closure behavior and comments, cross-checked against the matrix). They fail because the router does not exist yet.
- Tests are behavior-first: they assert targeting outcomes (which keys get reset/dismissed/idled), not router internals.
- Run the test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P17.05): <description> [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Introduce the router; port the closure targeting logic verbatim until the red tests pass — including the deliberate asymmetries the comments document (e.g. attention dismissal on a session-keyed window idles every sibling session for that origin, while Force Idle targets exactly its own slice; never all slices).
- Collapse the two factories into one parameterized factory that constructs the merged renderer (P17.04) and wires `panel.onX` handlers to router calls; side-effect dependencies (`StateJsonWriter`, pool tracker resets) are injected into the router, not reached from the factory.

## Refactor

- Delete the old duplicated closure bodies and their comment blocks in the same PR.
- Only refactor what you touched — `MenubarApp` beyond the factory/wiring seam is out of scope.

## Review Focus

- Targeting fidelity: the router must preserve every asymmetry the current comments document — sibling-session fan-out on dismiss, exact-slice Force Idle, combined-set resets, the "never all slices" rule protecting aged-out pets. These are the highest-risk lines in the phase.
- Ordering guarantees preserved: pool prompt-timer reset happens before the on-disk rewrite (the comment explains why); verify the router keeps the sequence.
- The factory is genuinely dumb: any residual conditional on window shape inside the factory is targeting policy that escaped the router.
- One disruption: confirm `MenubarApp` needed no wiring rework in P17.02–P17.04 that this ticket then redid.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `WindowActionRouterTests` failed to compile (`Cannot find type 'WindowActionRouter' in scope`) before the router existed; once it existed, `testForceIdleSessionKeyedResetsExactlyItsOwnSliceNeverAFresherSibling` flaked once on an unbounded async wait (see Deferred) before the completion-based fix.

Why this path: `WindowActionRouter` owns exactly the two duplicated handlers whose bodies branch on `WindowKey` shape — `onAttentionDismissed` and `onForceIdle` — ported verbatim (including the session-fan-out / exact-slice / combined-set / never-all-slices asymmetries and the prompt-timer-before-rewrite ordering) from the pre-existing closures. Both the own-window and minimalist-window factories construct one shared router instance and delegate to it, so the targeting policy and its explanatory comments now exist exactly once instead of twice.

Alternative considered: collapsing the own-window and minimalist-window factories into one literal `panel.onX = { router.handle(.x, for: key) }`-style parameterized factory (per the ticket's outcome wording) was rejected for this pass — `FloatingPetPanelController` and `MinimalistPanelController` are distinct concrete types with no shared action protocol, and unifying them was a materially larger, riskier change than this ticket's core ask (router-owned targeting policy, verified by unit tests). The two factories remain, but every duplicated *targeting* body inside them — the highest-risk lines per Review Focus — now delegates to the router; no parallel comment block describing dismiss/force-idle targeting survives.

Deferred: full single-factory unification across the own/minimalist controller types (would need a shared panel-action protocol — out of scope here); routing the non-targeting `onX` handlers (rename, sync label, prune, hide-all-other, mode-switch, open-settings) through the router — these have no `WindowKey`-shape branching to centralize, so leaving them inline is not policy duplication. `WindowActionRouterTests` initially waited on a fixed dispatch-queue round trip after the router's fire-and-forget async write; because `StateJsonWriter`'s target queue and the test's wait queue are independent, this raced and flaked. Fixed by adding an optional `completion` parameter to the router's two handlers (default `nil`, no behavior change for production call sites) and awaiting it via `XCTestExpectation` in tests.
Contract note: none.
