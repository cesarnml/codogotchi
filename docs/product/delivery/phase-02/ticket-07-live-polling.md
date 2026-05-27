# P2.07 Live polling — ~/.codogotchi/state.json + three failure visuals

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `apps/menubar/Sources/LivePollingDriver.swift` (or equivalent) polls the configured `pollingTarget` URL (from P2.06's seam) every 1 second on the main run loop.
- On each tick:
  - Read the file via `StateJsonReader` (P2.03).
  - On `.success(snapshot)`: if `snapshot.activity_state` differs from the previously rendered state, call `renderer.update(state: snapshot.activityState, visualMode: .normal)`.
  - On `.failure(.fileNotFound)`: render `.idle` with `.desaturated` visual mode; the menu-item tooltip reads `"codogotchi-hook not detected"`.
  - On `.failure(.malformed)` OR `.failure(.schemaMissingOrInvalid)`: render `.idle` with `.desaturated`; tooltip reads `"state.json schema_version is missing — codogotchi-hook may be too old"`.
  - On `.failure(.schemaNewer(got, expected))`: render `.idle` with `.desaturated`; tooltip reads `"state.json schema_version is v{got}; this app supports v{expected}. Update the menu bar app."` (formatted with the actual integers).
  - "Stale" (file present, valid, but `updated_at` is hours ago): no special handling — render the parsed `activity_state` normally. No upper bound on staleness initially (per the product plan).
- Tooltip wiring uses `NSStatusItem.button.toolTip`. Tooltip strings match the canonical copy in `docs/contracts/animation-state-vocabulary.md` (P2.02 appendix) character-for-character.
- Polling does not block the main thread on file I/O. Read is performed synchronously inside the timer callback (state.json is ~500 bytes; this is fine), but exceptions or errors do not escape into the run loop.
- Tests at `apps/menubar/Tests/MenubarTests/LivePollingTests.swift`:
  - Polling a path with no file present → renderer receives `(.idle, .desaturated)`; tooltip set to no-hook string.
  - Polling a path with `implementing.json` → renderer receives `(.implementing, .normal)`.
  - Polling a path with `schema-newer.json` → renderer receives `(.idle, .desaturated)`; tooltip set to schema-newer string with correct version numbers interpolated.
  - State change (e.g., file content swaps from `idle.json` to `implementing.json`) → renderer receives a single new `update(...)` call on the next tick.
  - Stale `updated_at` (hours old) but otherwise valid → renderer receives `(.idle, .normal)` for an `idle.json` payload (i.e., no stale handling).
- `notes/private/phase-02-swift-notes/P2.07-live-polling.md` lands in this PR explaining: timer ownership for polling, `Result` pattern matching in Swift, and string interpolation for tooltip formatting.

## Red

- Write `LivePollingTests` covering each failure visual and the happy-path transition. Run `bun run mac:test`; confirm failures.
- Commit `[red]`: `test(P2.07): live polling renders three failure visuals + happy path [red]`.

## Green

- Implement `LivePollingDriver` with a `Timer` running at 1Hz. Inject the polling target URL, the `StateJsonReader`, and the renderer (or a renderer-shaped protocol) for testability.
- Wire the driver into `MenubarApp.swift` as the default behavior when `CODOGOTCHI_DEMO` is unset (P2.06 set up the seam).
- Implement tooltip wiring on the same code path as the `visualMode` change.

## Refactor

- Confirm only one driver runs at a time — demo mode and live polling are mutually exclusive at launch.
- Confirm tooltip strings are sourced from a single Swift constants file (or matched exactly in tests against the contract doc's copy). Drift between tooltip and contract doc is a future-bug.
- Confirm last-rendered-state caching so the renderer is not called every tick with the same value (avoidable churn).

## Review Focus

- Tooltip copy matches the contract doc verbatim — if the contract doc said "may be too old" and the code says "might be too old," that's a deviation that should be caught here.
- The three failure visuals are *exhaustively distinguishable* (no two map to the same tooltip).
- Stale handling explicitly does *nothing* — no `updated_at` comparison code at all. Adding stale handling here would violate the locked product decision.
- Test seam: driver tests do not require a live `NSStatusItem` or real `~/.codogotchi/` directory.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Contract appendix update: P2.02's tooltip appendix initially listed only the two
schema-related tooltips. P2.07 surfaced a third failure visual (file absent at
the polling target — i.e., the hook binary is not installed). Adding the
canonical `codogotchi-hook not detected` copy to the contract appendix in this
PR keeps contract and code aligned per the existing drift rule. The two
schema-related strings were kept with their existing canonical spellings
(trailing period included for the schema-missing case); the test suite asserts
the exact tooltip values, so any future deviation is caught at PR review time.

Red first: each failure visual is asserted against a renderer stub before driver code exists.
Why this path: pure 1Hz polling chosen over `DispatchSource` / `FSEvents` for simplicity; no upper-bound staleness handling chosen to honor "quiet agent = idle pet is the truth."
Alternative considered: `DispatchSource + 5s poll fallback`. Rejected for code-path complexity.
Deferred: staleness thresholds (revisit only if live use shows a real failure mode); animated transitions between failure visuals.
Contract note: if any tooltip wording deviates from P2.02's contract appendix in implementation, update the contract doc *and* the code in the same PR — never let them drift.
