# Phase 18 Retrospective — Pool Pipeline Split (Derive / Diff / Apply)

## 1. Scope delivered

Seven tickets (P18.01–P18.07), PRs #175–#181, stacked on `v3_preview`. Replaced
`FloatingPetWindowPool.update()`'s ~1490-line imperative decision pipeline with
a pure `derive(input, memory) → (DesiredWindows, memory′)` fold, a mechanical
`PoolDiff`, and an effect-only `PoolApply`, built alongside the old pipeline
behind a shadow-compare safety net (P18.01–P18.05), cut over as authoritative
with the old pipeline demoted to a reversed shadow behind a
`CODOGOTCHI_POOL_ENGINE=legacy` rollback flag (P18.06), then deleted entirely
along with all shadow machinery and the flag (P18.07). A local dogfood DMG
(2.7.0, build 12 — unchanged) is packaged and running as the daily driver.
Public release, notarization, and Sparkle were explicit phase deferrals
(Track 2's workstream).

## 2. What went well

- **The Moore-machine fold structurally eliminated a named bug class rather
  than patching it.** P18.02's rationale documents that the imperative
  pipeline's Steps 5a/6a/6a2/6b exist only to detect and tear down stale
  entries in a persistent `windows` dictionary — four separate places a
  mode/shape/cap-membership mismatch can leak through. Because
  `PoolDerive.derive` recomputes desired membership from scratch every tick,
  there is no stale dictionary to mismatch against, so all four "mode-transition
  teardown" test rows passed with zero code written to detect a transition at
  all. This is the sharpest confirmation of the phase's central bet (Grill-Me
  decision 1): the fold didn't just make the bug classes easier to test, it
  made them unrepresentable.
- **The recording-proxy shadow design caught real coordinator bugs before
  cutover became the daily driver.** P18.06's subagent-review (codex-cli)
  found that the reversed-shadow's `LegacyPoolEngine` was constructed with a
  hardcoded empty hidden-keys loader while the new engine loaded the real
  persisted set — silently invalidating every hidden-window divergence
  comparison — plus two real staleness bugs (`sessionNumber` and
  `sessionDisplayLabel` surviving past teardown). All three were patched in a
  single `[subagent-review]` commit before `open-pr`. This is exactly the
  failure mode adversarial review exists to catch: a bug in the safety net
  itself, which a "does the ticket spec work" review would have missed
  because the net's job is to be quiet, not loud.
- **Per-ticket adversarial review prompts scoped to the actual diff kept
  findings dense and non-generic.** P18.01's subagent-review found a real gap
  in the purity-gate test's substring match (missed `import  AppKit` with
  double space, `@_exported import AppKit`, and `import class AppKit.NSWindow`
  variants) — a one-ticket-scoped, diff-specific finding that a generic
  "review this file" prompt would likely not have surfaced.

## 3. Pain points

- **Avoidable waste: ticket-06's Rationale section was never filled in.**
  `docs/product/delivery/phase-18/ticket-06-cutover.md`'s `## Rationale`
  still holds the unfilled template placeholders (`Red first: [what test
  failed first]`, etc.) at phase close. Every other ticket (P18.01–P18.05,
  P18.07) has a substantive, specific Rationale. This is a process gap, not
  an inherent cost — the ticket-completion checklist requires this section
  and nothing caught its absence before advancing past P18.06. Its absence
  directly compounds the pain point below: there is no recorded account of
  what P18.06 actually did with the five divergence classes P18.05 flagged.
- **Expected cost: the shadow-compare default-handler assert had to be
  walked back mid-phase.** P18.05's rationale documents that wiring
  `assert(divergences.isEmpty)` into the default `shadowDivergenceHandler`
  crashed ~13 pre-existing, ticket-unrelated tests the moment the shadow went
  live, because the still-maturing `derive` engine disagreed with the old
  pipeline on real field/scenario classes. The fix (default to a no-op
  handler, mirroring the established reader/writer injection pattern) was
  correct, but it means the "assert in tests/debug" half of Grill-Me decision
  4 never actually ran as a blanket assertion — it only runs where a test
  explicitly supplies a capturing handler. This is inherent to introducing a
  comparison engine against a not-yet-fully-matching baseline mid-build, not
  a design mistake, but it means the phase's automated regression net for
  divergences was narrower than the plan's language ("Asserts in tests/debug")
  implies.

## 4. Surprises

- **Five real derive/legacy divergence classes were found and explicitly
  deferred at P18.05, and none has a recorded resolution.** P18.05's
  Rationale names five field/scenario disagreements surfaced by running the
  full suite with the shadow live: `hudEnabled` tie-break order,
  `sessionNumber` assignment-order divergence, `conflictBubble` target
  selection, `sessionLabel`/`activityState` staleness on the `.combined` key
  during a transient empty-poll gap, and the permanently-exempted
  `inheritedFrameFrom` comparison. The rationale explicitly flags this as the
  P18.05→P18.06 pre-cutover soak's job to resolve, per the implementation
  plan's binding stop condition. P18.06's subagent-review found and fixed
  *different* bugs (hidden-keys loader, `sessionNumber`/`sessionDisplayLabel`
  staleness in the coordinator) but its own ticket doc's Rationale was never
  filled in, so there is no documented evidence any of the original five
  classes were resolved, confirmed as harmless, or even re-checked.
- **The P18.06→P18.07 deletion gate — a binding, developer-confirmation stop
  condition in the implementation plan and repeated in ticket-06's own
  Rationale footer — was not exercised.** No soak-summary doc or divergence
  log exists anywhere under `docs/product/delivery/phase-18/`. When asked
  directly during P18.07 delivery, the developer explicitly waived the gate
  rather than running the reversed-shadow rare-branch checklist, accepting
  the residual risk and stating unexpected behavior will be patched after
  landing on `v3_preview`. Combined with the previous point, this means the
  phase closes with a *known-open* question: whether any of the five
  divergence classes P18.05 found are still live in the pipeline that is now
  the only pipeline, with the rollback flag already deleted. This is
  recorded honestly in `docs/product/delivery/phase-18/exit-audit.md` §5, not
  glossed over — but it is the single most consequential fact in this phase
  for whoever reads this retrospective next.
- **Benign surprise: `PoolShadowComparator`, `RecordingFloatingPetWindowControllingProxy`,
  and `ShadowDivergenceLogger` were kept rather than deleted in P18.07.** The
  ticket's Outcome only explicitly named "the recording proxy and
  comparator" as things that "may survive only where tests use them."
  `ShadowDivergenceLogger` wasn't named but was judged in-scope for that
  allowance because its own test exercises it end-to-end with zero
  dependency on the deleted engine-selection wiring. P18.07's subagent-review
  confirmed no production entry point remains for any of the three. Worth
  knowing for a future reader who greps for these class names expecting them
  to be gone.

## 5. What we'd do differently

- **Make "fill in the ticket Rationale" a structural gate, not a checklist
  item to remember.** The ticket-completion checklist already names this
  requirement; ticket-06 slipping through anyway suggests the checklist
  alone isn't sufficient enforcement for a ticket whose actual outcome
  (resolving five named divergences) most needed the paper trail. A
  `post-verify` or `advance`-time check that a ticket's `## Rationale`
  section still contains the literal template placeholder text would have
  caught this before P18.07 started, when the gap was still recoverable.
- **The P18.06→P18.07 stop condition should have produced a
  machine-checkable artifact, not relied on the operator remembering to run
  a manual checklist and write a doc.** The implementation plan named the
  exact checklist (session cap overflow+eviction, grandfather admission both
  directions, hide-while-capped, manual Prune, three mode transitions, three
  window shapes) and named the exact artifact shape needed (a soak-summary
  doc, per the ticket's own Review Focus: "every logged divergence ... is
  either a ledger-entried old-pipeline fix, a matched new-engine fix, or the
  one named title-seam exemption"). In hindsight, a lightweight orchestrator
  gate — analogous to `post-verify`'s recorded-outcome pattern — that
  required a soak-artifact path before `start` on P18.07 would have made
  "waive this" a visible, deliberate override command instead of a silent
  absence discoverable only by reading three levels of docs.

## 6. Net assessment

The phase's core hypothesis — that a pure Moore-machine fold makes the Phase
15 QC bug classes structurally unrepresentable rather than separately
patched — held up under direct evidence (P18.02's teardown-step elimination)
and the shadow-compare mechanism itself proved its worth by catching three
real coordinator bugs before they reached the daily driver (P18.06's
subagent-review). The refactor's mechanical goal — `update()` is now
`derive → diff → apply`, the old pipeline and its rollback flag are gone —
is fully achieved and evidenced (exit-audit conditions 1, 2, 3, 4, 6: PASS).
The phase does **not** close with full confidence on behavior parity: five
named divergence classes from P18.05 have no recorded resolution, and the
binding pre-deletion soak gate was explicitly waived rather than satisfied.
Call the phase a structural success with an open behavioral-parity risk
carried forward, not a clean win.

## 7. Follow-up

- Run the P18.06→P18.07 reversed-shadow rare-branch checklist retroactively
  against the current `v3_preview` daily driver — the code paths still exist
  in git history (`agents/p18-06-cutover-and-role-reversal`) even though the
  shadow wiring itself is deleted, so this requires either a temporary local
  branch with the shadow restored or manual exercise of the checklist's six
  scenarios (session cap overflow+eviction, grandfather admission both
  directions, hide-while-capped, manual Prune, own/minimalist/combined
  transitions, all three window shapes) against plain observed behavior.
  Prioritize before any further Pool-adjacent phase starts.
- Specifically re-verify the five P18.05-named divergence classes against
  the current codebase: `hudEnabled` tie-break order on identical
  `updated_at`, `sessionNumber` assignment-order parity, `conflictBubble`
  target-selector agreement, `.combined`-key staleness during a transient
  empty-poll gap, and confirm `inheritedFrameFrom`'s permanent
  shadow-compare exemption was an accepted, documented behavior delta and
  not a masked bug.
- Add a `## Rationale`-not-template-placeholder check to the delivery
  orchestrator's `post-verify` or `advance` command so a ticket cannot
  silently advance without its Rationale filled in — file this against
  Track 2 or a future orchestrator-tooling ticket.
- Consider whether future phases with a binding pre-destructive-action stop
  condition (soak gates, migration point-of-no-return, etc.) should get a
  lightweight state-recorder command in the orchestrator, rather than relying
  on the operator to produce and the next agent to discover a prose artifact.

_Created: 2026-07-13. PR #181 open._
