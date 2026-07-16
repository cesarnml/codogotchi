# Phase 18: Pool Pipeline Split (Derive / Diff / Apply)

**Delivery status:** Approved and decomposed 2026-07-12 — delivery plan at `docs/product/delivery/phase-18/implementation-plan.md` (7 tickets). Awaiting preflight.

## TL;DR

**Goal:** Separate "which pets should exist" from "make it so" — restructure `FloatingPetWindowPool.update()` into a pure `derive` (policy), a mechanical `diff`, and an effect-only `apply`, so pool policy is directly testable and the Phase 15 QC bug classes become cheap table-driven cases instead of hunts through a ~10-step imperative pipeline.

**Ships:**

- Pure `derive()` producing a `DesiredWindows` value from the reader snapshot, customization, `SessionLifecycle` (Phase 16), hidden keys, cap/eviction policy, last-active election, grandfather gate, and combined folding — keyed by `WindowKey`, no AppKit imports.
- Mechanical `diff` — desired vs. current window set → spawn/dismiss/update sets, with frame-inheritance directives encoded as data.
- Effect-only `apply` — factories (Phase 17's converged shape), teardown, per-tick pushes; zero policy decisions.
- Migration via **parallel build + shadow-compare**: `derive` lands as unwired pure code, then a shadow tick runs both pipelines asserting identical decisions, then a single cutover — after which roles reverse (new drives, old shadows) through the closeout soak, and the old pipeline is deleted before phase exit.
- Named table-driven tests on `derive` covering every Phase 15 QC gap class; full existing suite (900+ tests) green against the composed whole.
- Local-only dogfood DMG at closeout. Closes Track 4; unblocks Track 2 (notarize + Sparkle) as the final v3 work item.

**Defers:** The v4 hook-stamped `prompt_started_at` architecture; any change to reader/writer disk contracts, clock defaults, or policy semantics (behavior freeze); randomized/property testing beyond the named gap classes (welcome stretch, not a gate); performance work; any public release.

---

Phases 16 and 17 delivered the vocabulary (`WindowKey`, `SessionLifecycle`) and the converged renderer/factory shape this phase consumes; both are closed with retrospectives written. Phase 18 is deliberately last in the Track 4 program so pool-pipeline regressions never share a dogfood window with view-layer regressions. The evidence base is the Phase 15 mainline sweep: nearly every QC fix — mode-transition teardown, eviction frame-inheritance, grandfather gating, hide/cap incumbency — was a 2–5-line condition gate inside `update()` missed because the pipeline's step-ordering invariants are implicit and its policy is only testable through side effects. This is the last chance to fix that shape before v4 (Stats tab, hook-stamped prompt timestamps) lands directly on this pipeline.

## Phase Goal

This phase should leave the product in a state where:

- "Who should be on screen" is answerable by calling a pure function with a snapshot, clocks, and hidden keys — no stub window controllers, no spawned windows.
- Each Phase 15 QC bug class (teardown on mode transition, hide/cap interaction, grandfather admission, eviction frame-inheritance) is a named table-driven test row against `derive`, demonstrably cheap to extend.
- `update()` (or its successor) is a composition of `derive` / `diff` / `apply`; the old imperative pipeline no longer exists in the codebase.
- The app behaves identically to the Phase 17 closeout build — full existing suite green, shadow-compare showed no unexplained divergence, and the dogfood build survives daily-driver use.

## Committed Scope

### Program invariants (binding on this phase)

- **Behavior bar: freeze + bug fixes.** Zero intentional user-visible change; `derive` must reproduce today's decisions exactly (as amended by the divergence policy below). Full existing suite green per ticket.
- **No big-bang.** Every ticket independently landable and behavior-neutral; unwired pure code and log-only shadow ticks satisfy this by construction.
- **Serial program.** Track 2 does not begin execution until this phase's exit condition and the Track 2 gate (below) are met.

### The pipeline split

- **`derive` (pure policy):** consumes the reader snapshot, customization, the three clocks via Phase 16's `SessionLifecycle` classifier, hidden keys, cap/eviction policy, last-active TTL-immunity election, grandfather gate, and combined folding; produces a `DesiredWindows` value keyed by `WindowKey`. No AppKit imports — enforced structurally (grep-verifiable), not by convention.
- **`diff` (mechanical):** desired vs. current window set → spawn / dismiss / update sets. Frame-inheritance directives (eviction promotion, grandfather collapse) are encoded as data in the diff, not as apply-time policy.
- **`apply` (effects only):** factories in Phase 17's converged shape, teardown, per-tick pushes (state, attention, gate badges, RPG state, labels, scale). Any policy decision found hiding in `apply` moves into `derive`.
- The exact `DesiredWindows` field spec, where grandfather-activation state and the session-number free-list allocator live, whether the last-active election is a derive step or an upstream clock-like input, and the channel shape for per-tick pushes are **decompose-level decisions** — the constraint they must satisfy is fixed here: `apply` makes zero policy decisions.

### Migration: parallel build + shadow-compare (decided in grill)

- `derive` is built ticket-by-ticket as pure, tested, **unwired** code behind the existing pipeline.
- A **shadow tick** then runs both pipelines every poll tick: the old pipeline drives the app; the shadow asserts the new one reaches identical decisions and logs any divergence. Strangler-style incremental peeling is explicitly rejected — the pipeline's danger is interleaving, and peeling re-exposes that bug class once per step.
- **Divergence policy (decided in grill):** when a divergence reveals the *old* pipeline is wrong, fix the bug in the old pipeline first, in a separate commit with a review-gap ledger entry (the standing program rule), then require the new engine to match. No bug-for-bug replication in `derive`.
- **Cutover** is a single ticket. After cutover, roles reverse: the new pipeline drives, the old one shadows through the closeout soak as a flag-flip rollback path.
- **Deletion of the old pipeline is a hard exit condition** — the phase does not end with two pipelines in the codebase.

### Test bar (decided in grill)

- Every Phase 15 QC gap class gets a named table-driven test against `derive`: mode-transition teardown, hide vs. cap incumbency, grandfather admission, eviction frame-inheritance. These double as coverage for the rare branches the shadow-compare cannot be expected to see during dogfood.
- Structural purity check: `derive` and its input/output types import no AppKit.
- Randomized/property testing across the full input space is a welcome stretch, **not** a phase gate.

### Closeout release (decided in grill: local-only)

- Package a dogfood DMG via the normal packaging script and install it as the daily driver. No public GitHub release, no download-page update — v3 ships with Track 2.

## Explicit Deferrals

- **v4 hook-stamped `prompt_started_at` architecture** (schema bump + hook binary + five installers) — a v4 item per the roadmap; this phase only ensures the pipeline it lands on is derivable and testable.
- **Any change to reader/writer disk contracts, clock defaults, or eviction/cap policy semantics** — behavior freeze; the only permitted behavior deltas are divergence-policy bug fixes with ledger entries.
- **Full property-based testing of `derive`** — the named-gap-class table tests are the gate; deeper generative testing is deferred to when v4 work actually extends the pipeline.
- **Performance work** — the pipeline runs once per poll tick; no budget change expected, and none is chased.
- **Public release / notarization / Sparkle** — Track 2's workstream; this phase's artifact is a local dogfood DMG only.

## Exit Condition

The phase is done when all of the following are demonstrably true on `v3_preview`:

1. **Composition:** the pool's update path is `derive` → `diff` → `apply`; the old imperative pipeline is deleted from the codebase.
2. **Purity:** `derive` is a pure function with no AppKit imports (grep-verifiable), consuming `SessionLifecycle` and `WindowKey` rather than raw clocks and strings.
3. **No hidden policy:** `DesiredWindows` + diff directives require zero additional policy decisions in `apply`, reviewed against every step of the former `update()`.
4. **Tests:** named table-driven tests cover all four Phase 15 QC gap classes; full existing suite green; `bun run verify` and `bun run ci:quiet` pass.
5. **Shadow evidence:** the pre-cutover shadow window and the post-cutover reversed-shadow soak completed with every divergence explained and resolved via the divergence policy.
6. **Dogfood:** a local DMG is packaged, installed, and running as the daily driver.

**Track 2 execution gate (decided in grill):** Track 2 execution starts only after (a) the dogfood build has served as daily driver with no unexplained regressions, **and** the soak has deliberately exercised the rare branches shadow-compare can't see by accident — session cap overflow/eviction, grandfather admission, hide-while-capped — plus all three window shapes (Own, Minimalist, Combined); no fixed calendar soak — and (b) the Phase 18 retrospective is written. Track 2 *planning* may proceed in parallel during the soak.

## Retrospective

`required` — architecture/process impact: this phase closes the Track 4 program and is the only phase that validates the derive/diff/apply bet itself; the retrospective is the program's closing verdict and is mechanically required by the Track 2 execution gate.
