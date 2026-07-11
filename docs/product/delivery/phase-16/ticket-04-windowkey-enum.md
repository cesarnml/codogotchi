# P16.04 WindowKey enum

Size: 3 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `WindowKey` exists in `Pool/`: `.origin(String)`, `.session(origin:id:)`, `.combined`, with `init?(rawValue:)` + `rawValue` as the **only** parse/serialize path in the target.
- `FloatingPetWindowPool` and `RenderKeyResolver` APIs take/return `WindowKey`; every consumer converted in the same PR (compiler-driven sweep, no string-based compatibility shims).
- Kill list satisfied: `grep -rn '"combined"' apps/menubar/Sources` hits only `WindowKey`'s own parse/serialize, persistence encode/decode boundaries (`app-state.json`, slice filenames), and test fixtures. Zero policy-site string checks.
- The colon-split sites are gone: `FloatingPetWindowPool` lines ~241/253 (`origin(forKey:)`, `sessionID(forKey:)`), `RenderKeyResolver:110`, `GateJsonReader:210` — all replaced by `WindowKey` matching or its raw-value boundary.
- Full existing suite green; only new tests added are `WindowKey`'s own.

## Red

- Write `WindowKeyTests` first: parse/serialize round-trip for all three cases, invalid-input rejection (`init?` returns nil), and the exact raw-string forms currently persisted (`"combined"`, bare origin, `origin:sessionID`) so the serialization format is pinned before any call site changes.
- Run the suite and confirm the new tests fail (type does not exist).
- Commit with suffix `[red]`: `test(P16.04): WindowKey parse/serialize round-trip [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Implement `WindowKey` in `Pool/WindowKey.swift`; raw-value format must byte-match the current string convention (this is a serialization contract, not a design surface).
- Switch `FloatingPetWindowPool` and `RenderKeyResolver` public APIs from `String` keys to `WindowKey`; let the compiler enumerate every consumer and convert each to enum matching.
- Strings survive only at true boundaries: `app-state.json` persistence encode/decode, slice-filename construction, and test fixtures — each converts at the edge via `init?(rawValue:)` / `rawValue`.

## Refactor

- Delete the now-dead string helpers (`origin(forKey:)`, `sessionID(forKey:)`, resolver colon parsing) — do not leave deprecated wrappers.
- No opportunistic changes to pool behavior or `update()` structure (Phase 18).

## Review Focus

- Run the kill-list grep and the colon-split grep in review; paste results into the PR.
- Every conversion site: is the enum *matched* (policy) or *round-tripped* (boundary)? Round-trips outside the sanctioned boundaries are the anti-pattern this ticket exists to kill.
- Raw-value byte-compatibility with persisted `app-state.json` keys and slice filenames — a format drift here corrupts state silently on upgrade.
- No behavior change in key resolution order or fallback semantics.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: WindowKey round-trip tests fail (type absent)
Why this path: switching pool APIs makes the sweep compiler-exhaustive; shims would ship dual representation mid-phase
Alternative considered: two tickets with string-overload shims — rejected in grill (dual-truth window + third cleanup PR)
Deferred: any `update()` pipeline changes (Phase 18); renaming render-key concepts

Implementation notes (post-sweep):
- `GateJsonReader.swift`'s `originAndSession(of:suffix:)` (~line 206) is renamed `sessionWindowKey(of:suffix:)` and now returns `WindowKey?` directly (constructing `.session(origin:id:)` from the parsed halves) instead of a raw `(origin, sessionId)` tuple. The colon split itself could not be eliminated — a `<origin>:<session_id>.gate.json`/`.context.json` filename is not a bare `WindowKey` rawValue, it carries a suffix and (defensively) surrounding whitespace — so this stays a boundary parse, per the ticket's own guidance, but its output is the typed key rather than a tuple a caller would have to re-join into a string.
- `StateJsonReader.parseSliceFilename` (a second, independent filename-boundary parser for `state.d/` slice files, not named in the ticket's kill list) was left as a raw `(origin, sessionId)` tuple — out of this ticket's explicit scope (`FloatingPetWindowPool`/`RenderKeyResolver` public APIs). Its callers already convert the pair into `WindowKey` at their own call sites where a typed key is needed.
- The sweep additionally touched `SessionSelectionPolicy.swift`, `ConflictBubbleTargetSelector.swift`, `PerPlatformSnapshot.swift`, `SessionsTabViewModel.swift`, and `AppState.swift` (`app-state.json`'s `floating_pet_positions`/`floating_pet_hidden` boundary) — not in the ticket's "known call sites" list, but required by the compiler once `FloatingPetWindowPool`'s internal dictionaries and `PerPlatformSnapshot`'s fields became `WindowKey`-keyed, matching "let the compiler enumerate every consumer."
- Added `WindowKey: ExpressibleByStringLiteral` (delegating to `init?(rawValue:)`, degrading a malformed literal to `.origin(value)`) purely for test-fixture ergonomics — the ticket's sanctioned "test fixtures" raw-string boundary. No production call site relies on it; production code always constructs `WindowKey` via `.origin`/`.session`/`.combined` or `init?(rawValue:)`.
- `SessionLabelStore`/`RetrievedSessionTitleStore`/`SessionPruner` (session-labels.json, retrieved-session-labels.json, and slice-filename construction) were left `String`-keyed — the same persistence/filename-boundary category as `app-state.json`, just not renamed to accept `WindowKey` directly since they sit outside `FloatingPetWindowPool`/`RenderKeyResolver`'s public surface. `FloatingPetWindowPool`'s default reader/writer closures convert via `.rawValue` at exactly that call boundary.
- `AssignmentsJsonReader.resolve(origin:)`'s `"combined"` and `PlatformAttribution.init?(origin:)`'s `"combined"` remain `String` comparisons by design — both decode a *different* "combined" concept (a pet-assignment slot name, and a `source_event.origin` wire value, respectively) that merely shares the literal string with the window-key `.combined` case; verified via full-codebase trace before leaving them untouched.
