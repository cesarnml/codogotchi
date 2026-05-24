# P3.03 Swift ActivityState 4→15 + Codex sheet row expansion

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `apps/menubar/Sources/ActivityState.swift` is a closed enum with all 15 cases: `idle`, `implementing`, `runningTests`, `reviewing`, `pushing`, `hyped`, `focused`, `nervous`, `waiting`, `celebrating`, `ascended`, `callingForBackup`, `panicking`, `requestingInput`, `errored`.
- The decoder's "unknown string → `.idle`" fallback still applies — any hook-emitted state not in the closed enum still decodes as `.idle` without crashing.
- `apps/menubar/Sources/MaliPet.swift` (or its Phase 03 equivalent — kept named `MaliPet` for git history continuity even though the loader is pet-agnostic) extends its `rowMap` to include the three additional Codex-sheet-served states per the contract's "Spritesheet Asset Layout" table:
  - `.waiting` → row 6 (8 frames)
  - `.requestingInput` → row 3 (8 frames)
  - `.errored` → row 5 (8 frames)
- The nine codogotchi-owned states (`celebrating`, `hyped`, `focused`, `nervous`, `ascended`, `callingForBackup`, `panicking`, `reviewing`, `pushing`) are **not** mapped in the Codex `rowMap` and continue to fall back to `.idle` rendering until P3.04 lands their loader.
- The Phase 02 `celebrating` mapping (currently `RowSpec(rowIndex: 4, frameCount: 5)` from Codex row 4 / `jumping`) is **removed** from `MaliPet.rowMap` — `.celebrating` now waits for the codogotchi sheet in P3.04. Between P3.03 and P3.04, `.celebrating` renders as `.idle`. This is an honest intermediate.

## Red

- Write a test that `ActivityState(rawValue: "requesting_input")` returns the `.requestingInput` case.
- Write a test that `ActivityState(rawValue: "errored")` returns the `.errored` case.
- Write a test asserting all 15 cases exist (e.g., `ActivityState.allCases.count == 15` if `CaseIterable` is added — otherwise an explicit enumeration test).
- Write a test that `MaliPet.rowMap[.waiting]?.rowIndex == 6`.
- Write a test that `MaliPet.rowMap[.requestingInput]?.rowIndex == 3`.
- Write a test that `MaliPet.rowMap[.errored]?.rowIndex == 5`.
- Write a test that `MaliPet.rowMap[.celebrating]` is `nil` (intermediate state — codogotchi sheet owns this in P3.04).
- Write a test that `.frames(for: .waiting)` returns 8 frames, all cropped from row 6 at the correct cell rect.
- Write a regression test that `.frames(for: .idle)` still returns 8 frames from row 0 (Phase 02 contract preserved).
- Run `xcodebuild test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P3.03): swift enum 4→15 + codex sheet expansion [red]`.

## Green

- Expand the `ActivityState` enum in `ActivityState.swift` to all 15 cases. Raw values match the hook's emitted strings exactly (snake_case as in the contract: `running-tests`, `requesting_input`, `calling_for_backup`, etc.).
- Extend `MaliPet.rowMap` with the three new Codex-served entries.
- Remove the existing `.celebrating: RowSpec(rowIndex: 4, frameCount: 5)` entry. The Codex `jumping` row (4) is being released — it returns to "reserved for future float sprite" per the contract.
- Update any exhaustive `switch` on `ActivityState` (renderer, demo cycler, transition log writer) to handle the new cases. New cases fall through to the existing `.idle` rendering path until P3.04 wires sheets — explicit cases, not `default:`.

## Refactor

- The `MaliPet` filename can stay as-is for git history. Internal type rename is out of scope for this ticket — it can be revisited in P3.04 alongside the new `CodogotchiPet` if the naming asymmetry becomes confusing.
- If any `switch` statement was relying on a `default:` clause, replace it with explicit cases. Closed-enum discipline lives in the renderer, not just the contract.
- Do not opportunistically restructure the renderer for the new sheet — P3.04 owns that change.

## Review Focus

- All 15 cases are present in the enum and raw values match the contract exactly (snake_case, hyphenated for `running-tests`).
- No `default:` catch-alls in switches over `ActivityState`. Every case is named, even if its branch body is `// rendered as idle in Phase 03 — wired in P3.04`.
- The Codex `rowMap` has exactly seven entries after this ticket: `.idle`, `.implementing`, `.runningTests`, `.waiting`, `.requestingInput`, `.errored`, plus any Codex-served state I missed (review against the contract's Codex Sheet table).
- The `.celebrating` removal is intentional — confirm the test asserting `rowMap[.celebrating] == nil`.
- The renderer between P3.03 and P3.04 paints 6 of 15 states from sprite rows; the other 9 fall back to `.idle`. This is correct.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Build error: `type 'ActivityState' has no member 'waiting'` — the first missing case that prevented the Red test class from compiling.
Why this path: Adding 11 enum cases and updating the rowMap is the minimal change. No switches over ActivityState exist in the codebase, so no fallthrough handling was needed.
Alternative considered: Keeping a `default:` in the renderer if any switch existed, rather than explicit case handling. Rejected per ticket spec — closed-enum discipline requires explicit cases even when the body is a no-op. (No switches were present in practice.)
Deferred: `EXPECTED_STATE_SCHEMA_VERSION` bump in `StateJsonReader.swift` — P3.04 ticket owns that. `CodogotchiPet` type rename from `MaliPet` — also deferred to P3.04. Demo cycle extension beyond 4 states — P3.06.
Contract note: `unknown-state.json` fixture updated from `"ascended"` (now a valid enum case) to `"future_unknown_state"` to keep the unknown-state fallback test honest.
