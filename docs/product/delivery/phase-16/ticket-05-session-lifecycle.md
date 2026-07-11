# P16.05 SessionLifecycle enum + classifier

Size: 2 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `SessionLifecycle` exists in `Pool/`: `.active`, `.live`, `.archived`, `.pruned`, plus a single pure classifier function consuming the three clocks (dismiss TTL, reader staleness, prune horizon).
- Both existing consumers are rewired to it in the same PR: `SessionsTabViewModel` bucketing and menubar lifecycle tiering. Neither re-derives lifecycle from raw clocks afterward.
- The classifier is the only lifecycle-judgment site in the target; Phase 18's `derive()` will consume this type.
- New classifier unit tests exist; **all existing consumer tests pass unmodified** — that is the behavior-neutrality proof.

## Red

- Write `SessionLifecycleTests` first: table-driven cases over the three clocks covering each state, each boundary (exactly-at-TTL, exactly-at-horizon), and clock-combination precedence — encoding the *current* bucketing/tiering behavior, discovered by reading `SessionsTabViewModel` and the tiering site, not by inventing desired behavior.
- Run the suite and confirm the new tests fail (type does not exist).
- Commit with suffix `[red]`: `test(P16.05): SessionLifecycle classifier over three clocks [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Implement `Pool/SessionLifecycle.swift` with the enum and classifier as a pure function (clocks in, state out — no I/O, no time source of its own; callers pass `now`).
- Rewire `SessionsTabViewModel` bucketing to classify then match on the enum.
- Rewire menubar lifecycle tiering to the same classifier.
- If the two consumers turn out to disagree about a boundary today (e.g. `>=` vs `>` on a TTL), **stop** — that is a genuine pre-existing bug candidate per the implementation plan's stop conditions; do not silently unify.

## Refactor

- Remove the now-dead inline clock comparisons from both consumers.
- No opportunistic changes to TTL values, tier ordering, or bucketing labels.

## Review Focus

- Classifier purity: no hidden `Date()` / I/O inside; `now` injected.
- Consumer-test invariance: existing `SessionsTabViewModel` and tiering tests unmodified and green — flag any test edit as a spec violation.
- Boundary semantics: each `>=`/`>` in the classifier traceable to the pre-existing consumer code it replaced.
- Precedence when clocks conflict (e.g. stale but not yet pruned) matches prior behavior exactly.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: classifier table tests fail (type absent)
Why this path: one ticket rewiring both consumers avoids a dual-source-of-truth window; `Pool/` per drawer glossary (session policy)
Alternative considered: split "classifier + VM" / "tiering" tickets — rejected; half-adopted type is the disease itself
Deferred: `derive()` consumption (Phase 18); any lifecycle behavior change

Implementation note: `SessionLifecycle.classify(age:isRendered:isConcealed:liveTTL:archiveTTL:)`
takes `isConcealed` as one collapsed boolean (hidden-by-user OR pending-show OR
idle-dismissed) rather than three separate flags — the classifier only needs
"is this key currently concealed" to pick the tier; which specific concealment
reason applies only matters for `isShown`/`pendingShowKeys` bookkeeping, which
stays in `SessionsTabViewModel.refresh()`'s per-branch `if/else` (unchanged
precedence: rendered > hidden-by-user > pending-show > idle-dismissed) rather
than the pure classifier. `MenubarMenu`'s "lifecycle tiering" already fully
delegates to the shared `SessionsTabViewModel` instance (no independent clock
comparisons of its own), so it required no code change — only
`SessionsTabViewModel` needed rewiring. No consumer disagreement was found;
the extraction is behavior-neutral (full existing suite green, 1038/1038
after the new classifier tests).
