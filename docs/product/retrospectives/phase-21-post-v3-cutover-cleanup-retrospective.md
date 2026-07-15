# Phase 21 — Post-v3 Cutover Cleanup Retrospective

## Scope delivered

Five stacked tickets off `v3_preview`: [P21.01](https://github.com/cesarnml/codogotchi/pull/190) deleted the Phase-18-retained shadow trio (`PoolShadowComparator`, `RecordingFloatingPetWindowControllingProxy`, `ShadowDivergenceLogger`) plus orphaned harness tests, regenerated `Codogotchi.xcodeproj`, and scrubbed five present-tense P18 “not yet” lies; [P21.02](https://github.com/cesarnml/codogotchi/pull/191) audited `foldedSessionDisplay` as prune-only and removed it end-to-end, collapsing prune titles to bare `FloatingPetHidePrompt.pruneTitle`; [P21.03](https://github.com/cesarnml/codogotchi/pull/192) removed `applyPromptTimerStatus` from production pool-facing protocols while keeping Own/Minimalist local heartbeat/override-clear as private `applyLocalPromptTimerStatus`; [P21.04](https://github.com/cesarnml/codogotchi/pull/193) made `SessionPruner` disk-only, deleted class `SessionNumberAllocator`, and migrated numbering tests onto `SessionNumberAllocatorState` / `PoolMemory`; [P21.05](https://github.com/cesarnml/codogotchi/pull/194) (this ticket) updated lying developer notes, filed this retrospective, and packaged/installed a local dogfood DMG with no public release.

## What went well

- **Delete-not-relocate for the shadow trio was the right call, and grep-backed Red proofs made the outcome auditable without a soak gate.** P21.01’s absence tests and post-green greps under `apps/menubar` prove the utilities are gone from the app target; that is a stronger delivery signal for “not live architecture” than another reversed-shadow checklist that Phase 18 already waived. Naming the Phase 18 soak waiver explicitly in the product plan and ticket Outcome forced the retrospective (here) to record the decision rather than quietly re-opening QA debt mid-hygiene.
- **Prune-only audit before deleting `foldedSessionDisplay` kept the behavior freeze honest.** P21.02’s Rationale enumerated DesiredWindow → derive → PoolApply → protocols → views → prompts and confirmed every live read fed prune copy. Full E2E delete followed from evidence, not from “it looks unused.” That audit-first pattern is reusable for any half-dead push field where a keep-vs-delete stop condition exists.
- **Private helpers for timer heartbeat preserved cadence without re-advertising a dead protocol method.** P21.03 narrowed the production surface to presentation-only while keeping local `Timer` heartbeats as `@testable` internals — matching the grill decision that “presentation-only” means one *production push*, not “delete every status method.” Freeze-adjacent timer feel did not have to invent derive-only sub-second ticks.
- **Allocator unify was mechanical once the live caller grep was clean.** P21.04 confirmed no production class-allocator caller beyond the prune throwaway fiction, then stripped the Pruner parameter and deleted the class. Number release stayed solely in `memory.pruning` / `SessionNumberAllocatorState` — the dual free-list fiction disappeared without touching assign/reuse semantics.

## Pain points

- **Avoidable waste: surface-scan tests that only search a lowercase token invited a false sense of contract strength.** P21.04’s adversarial review flagged that `SessionPrunerAllocatorSurfaceTests` claimed “no allocator parameter or release” while only scanning for `"allocator"`, which would miss a rename like `numbering.release(...)`. The primary agent patched the assertion (ledger `patched` row); the lesson is that freeze-critical regression tests should assert the *behavior or named API*, not a single substring synonym for the deleted type.
- **Expected cost: doc-comment drift after rename/delete of types.** Several Sources comments still named `SessionNumberAllocator` after the class deletion (badge, menubar menu display-name helper, `CustomizationJsonReader` default-cap docs). P21.05 scrubbed those as lying developer notes. Comment consumers are easy to miss when Red tests only grep for type *declarations* and constructions.

## Surprises

- **`Menubar.xcodeproj` was already absent on `v3_preview` — P21.01 had nothing to delete for the husk.** The ticket Outcome still held (husk gone; Codogotchi.xcodeproj remains), and the Rationale honestly recorded the no-op. Future “delete husk X” tickets should check base tip existence in Red planning so the PR body does not imply a spectacular deletion that never happened.
- **Phase 18 waived reverse-shadow soak; Phase 21 deleted the last shadow utilities without re-introducing a soak gate.** That is intentional product posture, not an accident: the waived P18.06→P18.07 rare-branch checklist and P18.05-named divergence classes remain explicit deferrals (QA/product debt), not leftovers this hygiene phase was authorized to reopen. Anyone planning Track 2 or a “finish soak gaps” phase should start from Phase 18’s retrospective follow-ups, not assume Phase 21 silently closed them by deleting the harness.
- **Freeze-adjacent surprises in P21.02–04 were mostly semantic surface, not UX deltas.** Fold-display removal only dropped a discarded parameter path that already returned a constant; timer work kept local heartbeats; allocator delete removed a no-op release path while pool release-before-prune stayed. The freeze held — the surprises were about honesty of tests/docs (husk already gone; test-scan weakness; comment drift), not about shipping a different timer/prune feel.
- **Subagent review recorded `clean` then an operator `patched` row on P21.04** after the primary agent applied the Medium actionable finding on the surface-scan assert. Reconciliation required an explicit patched path rather than pretending the first clean row still described HEAD — same ledger discipline Phase 14 introduced, and it worked.

## What we'd do differently

- **Write absence Red tests against the real contract (named API + double-release behavior), not a single lowercase token.** The original P21.04 scan would have graded green while still allowing a sneaky double-release rename; adversarial review caught it, but the ticket’s own Review Focus already named “exactly one release.” Spec-authored Red tests should have encoded that stronger assertion from the start.
- **Bundle a “stale identifier comment scrub” checklist into any delete-type ticket** (or accept that closeout P21.05 will keep finding them). Grep for the deleted type name in `Sources/**/*.swift` comments as a post-green step on the same ticket that deletes the type, not only as a closeout leftovers pass.

## Net assessment

Phase 21 achieved its forcing-function goal under the behavior freeze: shadow utilities are gone from the menubar app without a new soak gate; prune titles no longer thread discarded fold-display strings; production protocols expose one prompt-timer push; session numbering has a single owner (`SessionNumberAllocatorState` / `PoolMemory`) with disk-only `SessionPruner`; lying present-tense cutover comments and remaining `SessionNumberAllocator` doc references are scrubbed; suite adjusted for deleted subjects; local dogfood DMG installed. Deferred items (flat-gate fallback, Own/Minimalist extract, waived soak gaps, public release) remain deferred on purpose.

## Follow-up

- Treat Phase 18’s waived reverse-shadow rare-branch checklist and unresolved P18.05 divergence classes as a named QA/product follow-up phase or standalone — do **not** reopen them as silent Phase 21 debt; the delete-without-re-soak decision is recorded here as deliberate.
- Optionally promote “absence tests assert named API / double-release behavior, not synonym substrings” into the adversarial-review template’s freeze-critical surface class (via the review-gaps promotion queue) if it recurs.
- Flat-gate production fallback removal and Own/Minimalist shared timer extraction remain explicit Phase 21 deferrals — pick them up only via a new grilled plan, not a drive-by closeout ticket.

_Created: 2026-07-15. PRs #190–#194 open, stacked, awaiting developer review and `closeout-stack`._
