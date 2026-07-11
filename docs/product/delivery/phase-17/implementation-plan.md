# Phase 17 — Surface Convergence ("One Renderer, Two Skins")

> Converge the three window shapes (Own / Minimalist / Combined) onto one prompt/dismissal component, one chrome-flock coordinator, one renderer protocol, and one targeting router — with zero intentional user-visible change — so a fix or affordance lands once instead of three times.

## Epic

Track 4 architectural consolidation (Phases 16 → 17 → 18). Product plan: `docs/product/plans/phase-17-surface-convergence.md`. Phase 16 closed 2026-07-12; this phase builds on its layer directories, god-file splits, and `WindowKey`.

## Product contract

No user-visible change — that is the contract. When this phase is complete a developer can:

- Write a prompt or dismissal fix once: exactly one dismissal observer stack and one `[PromptItem]` builder exist, with per-shape differences expressed as capability parameters.
- Implement a window-shape behavior against one renderer protocol; `MenubarApp` wiring contains no parallel comment blocks kept honest by hand.
- Rely on one chrome-flock coordinator for badge/bubble/HUD anchoring, drag routing, and fronting across all three shapes, reproducing current per-shape behavior verbatim.
- Audit cross-surface parity by diffing code against the developer-approved capability matrix at `docs/contracts/window-capability-matrix.md`, with intentional differences named as capabilities.
- Run the app from a locally packaged dogfood DMG that behaves identically to the Phase 16 dogfood build.

## Grill-Me decisions locked

- **Spine: matrix → prompt → chrome → renderer → router → closeout** → the prompt component is the smallest proven seam and pure view-layer; the chrome coordinator extracts anchoring/drag/fronting from the panel controllers *before* protocol convergence so the merged protocol is born consuming the coordinator; renderer + router go last so `MenubarApp` is disrupted exactly once, when everything it wires is final.
- **Renderer protocol and Seam-2 router are two tickets, not one** → the protocol merge is mechanical `Windows/`-layer work reviewable as "signatures unify, bodies unchanged"; the router ticket owns the single `MenubarApp` disruption and gives the (currently untested) targeting logic its own focused PR with new unit tests.
- **Drift-bug restorations land inside the convergence ticket that owns that surface, as separate ledger-flagged commits** → restoring drift *before* convergence means writing the fix N times per surface (the anti-pattern this phase kills); the matrix ticket stays doc-only. Mirrors the Phase 16 separate-commit rule.
- **Chrome coordinator is one ticket, staged commit-per-shape** → a coordinator adopted by some shapes across ticket boundaries is the dual-source-of-truth window where every coordinator fix must be hand-mirrored; the PR stages coordinator + tests, then Own, Minimalist, Combined migrations, then dead-code deletion as reviewable commits.
- **Prompt-affordance matrix rows are enforced as table-driven unit tests; the rest of the matrix stays doc + closeout audit** → the `[PromptItem]` builder is pure and cheap to test against exact per-shape output, and prompts are the proven 3×-fix pain point; chrome/drag/rename behavior is not unit-testable without heavy scaffolding.
- **Matrix lives at `docs/contracts/window-capability-matrix.md`** → it is a durable contract that Phase 18 and v4 amendments reference, not phase ephemera; mid-phase amendments only land in commits citing explicit developer sign-off.
- **Matrix is ticket P17.01 with an orchestrator stop point for developer disposition** → the archaeology is tracked phase work with its own PR; the serial spine blocks all convergence tickets until the approved matrix is committed, so nothing lands against an undispositioned grid.

## Ticket Order

1. `P17.01 Capability matrix (drafted from code, developer-dispositioned)`
2. `P17.02 Shared prompt/dismissal component`
3. `P17.03 Chrome-flock coordinator`
4. `P17.04 Renderer protocol merge`
5. `P17.05 Seam-2 router + factory collapse`
6. `P17.06 Closeout: exit audit + dogfood DMG + retrospective`

## Ticket Files

- `ticket-01-capability-matrix.md`
- `ticket-02-shared-prompt-dismissal.md`
- `ticket-03-chrome-flock-coordinator.md`
- `ticket-04-renderer-protocol-merge.md`
- `ticket-05-router-factory-collapse.md`
- `ticket-06-closeout-dogfood-retro.md`

## Exit Condition

All six conditions from the product plan hold on `v3_preview`, with evidence recorded in P17.06:

1. **One prompt system:** exactly one dismissal observer stack and one prompt-item builder exist; no surface owns a private `presentHidePrompt`.
2. **One renderer protocol:** `FloatingPetPanelManaging` and `MinimalistPanelManaging` no longer exist as separate protocols; the router owns targeting; `MenubarApp` factory wiring is deduplicated with no parallel comment blocks.
3. **One chrome coordinator:** badge/bubble/HUD anchoring, drag routing, and fronting are implemented once and consumed by all three shapes, per-shape behavior verbatim.
4. **Matrix matches code:** the approved matrix at `docs/contracts/window-capability-matrix.md` is committed; the code audit shows every affordance present per the matrix, every intentional difference named as a capability, and every restored-drift fix carrying a review-gap ledger entry.
5. **Behavior bar:** full existing suite green; `bun run verify` and `bun run ci:quiet` pass.
6. **Dogfood:** a local DMG is packaged, installed, and running as the daily driver. No public GitHub release, no download-page change.

**Phase 18 execution gate (phase-transition condition, not ticket work):** Phase 18 execution starts only after (a) the dogfood build has soaked as daily driver with no unexplained regressions, with the soak explicitly exercising all three window shapes (Own, Minimalist, Combined — the three-shape checklist is part of the gate, no fixed calendar), and (b) the Phase 17 retrospective is written. Phase 18 planning may proceed during the soak.

## CI Baseline

Run `bun run ci:quiet` on `v3_preview` before P17.01 starts and record the result here. This snapshot makes per-ticket CI diffs unambiguous — an agent can tell whether a failure is pre-existing or introduced.

> Baseline recorded: [date] — [pass / N pre-existing errors: brief summary]

## Review Rules

- Tickets must be merged in order (P17.01 → P17.06); the spine is strictly serial.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- Behavior bar applies per ticket: full existing suite green; existing tests modified only where a ticket's spec explicitly sanctions it.
- Zero intentional user-visible change, with one exception: drift rows the developer dispositioned `bug` in the approved matrix are restored as **separate commits** inside the convergence ticket owning that surface, each with a review-gap ledger entry. No restoration commit may land before its matrix row is dispositioned.
- Matrix amendments (missed affordances discovered mid-phase) require developer sign-off before `docs/contracts/window-capability-matrix.md` changes; the amending commit cites the sign-off.
- Per-shape behavior differences dispositioned `intentional` are reproduced verbatim as named capabilities — never converged away.

## Explicit Deferrals

- **`update()` pipeline restructuring (derive/diff/apply)** — Phase 18's workstream; this phase touches the view layer and factory wiring, not pool policy.
- **New affordances of any kind** — the matrix documents what exists; adding rows is v4 work.
- **Re-anchor cadence, screen-edge behavior, and Chapter-14 chrome tuning** — the coordinator unifies mechanics only; changing when/how chrome re-anchors is behavior change and out of the program bar.
- **Intentional behavior changes** — including "while we're in here" improvements; anything user-visible found broken is a separate-commit bug fix with a ledger entry, gated by matrix disposition.
- **Public release / notarization / Sparkle** — Track 2; this phase's artifact is a local dogfood DMG only.

## Stop Conditions

- **P17.01 disposition stop (mandatory):** after the drift grid is drafted, stop for developer row-by-row disposition before committing the matrix. Default under uncertainty is `intentional, documented` — never `fix` — and the default is only applied with the row visible to the developer.
- A cross-shape affordance is discovered mid-ticket that has no matrix row: stop for developer sign-off on the amendment before proceeding.
- A convergence step cannot reproduce a shape's current behavior verbatim without a behavior change: stop and surface it as a proposed matrix row rather than converging silently.
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Architecture/process impact — Phase 18 restructures `update()` on top of this phase's renderer protocol and chrome coordinator; the retro validates the view-layer foundation before the pool pipeline inherits it, and it is mechanically required by the Phase 18 execution gate.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-17-surface-convergence-retrospective.md`
