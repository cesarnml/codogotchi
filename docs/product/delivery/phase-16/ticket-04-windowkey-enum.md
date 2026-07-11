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
