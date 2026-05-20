# P2.03 Swift StateJsonReader — parse + schema policy + unknown-state fallback

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `apps/menubar/Sources/StateJsonReader.swift` exposes a `StateJsonReader` type (or namespace) that takes a file path and returns a `Result<StateSnapshot, StateReadError>` (or equivalent shape).
- `StateSnapshot` decodes the `state.json` v1 schema fields used by the renderer: `schema_version`, `activity_state`, `updated_at`. (`hp_overlay`, `hp`, and `source_event.*` fields are parsed but tolerated as optional; Phase 02 does not render them.)
- `activity_state` is decoded into a closed-enum `ActivityState` covering at least the four floor states (`.idle`, `.implementing`, `.runningTests`, `.celebrating`). All other contract-listed states are decoded as `.idle` (the unknown-state → idle fallback) so the app never crashes on an unknown enum value.
- Schema-version policy implemented per P2.02's contract clause:
  - `schema_version` field missing or non-integer → `Result.failure(.schemaMissingOrInvalid)`.
  - `schema_version > EXPECTED_STATE_SCHEMA_VERSION` (compile-time constant `= 1`) → `Result.failure(.schemaNewer(got: Int, expected: Int))`.
  - `schema_version <= EXPECTED_STATE_SCHEMA_VERSION` → `Result.success(snapshot)`, ignoring unknown fields.
- File-not-found → `Result.failure(.fileNotFound)`. Unparseable JSON → `Result.failure(.malformed)`.
- `apps/menubar/Tests/MenubarTests/StateJsonReaderTests.swift` covers (each is a separate test method):
  - `idle.json` parses to `.idle` activity state.
  - `implementing.json`, `running-tests.json`, `celebrating.json` each parse to their respective enum cases.
  - `unknown-state.json` (contains `"activity_state": "ascended"`) parses to `.idle` per the fallback rule.
  - `schema-newer.json` (contains `"schema_version": 99`) returns `.failure(.schemaNewer(got: 99, expected: 1))`.
  - Missing file path returns `.failure(.fileNotFound)`.
  - Malformed JSON returns `.failure(.malformed)`.
- Fixtures used by tests live at `apps/menubar/Fixtures/state-json/` and are committed in this PR.
- `notes/private/phase-02-swift-notes/P2.03-state-json-reader.md` lands in this PR with a TS-developer-perspective explanation of the new Swift concepts used (e.g., `Codable`, closed-enum decoding, `Result`-vs-throws idiom, optional decoding, decoding into a typed struct with `JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase`).

## Red

- Write `StateJsonReaderTests` covering all listed cases first. Run `bun run mac:test`; confirm every test fails because `StateJsonReader.swift` does not yet exist (or is stub-only).
- Commit with suffix `[red]`: `test(P2.03): state-json-reader covers four floor states, unknown fallback, schema policy [red]`.
- Do not write any implementation until this commit exists on the branch.

## Green

- Create the six fixture JSON files at `apps/menubar/Fixtures/state-json/` (`idle.json`, `implementing.json`, `running-tests.json`, `celebrating.json`, `schema-newer.json`, `unknown-state.json`). Add `unknown-state.json` with a real contract state name that Phase 02 doesn't render (e.g., `"ascended"`).
- Implement `StateJsonReader` with a `Codable` `StateSnapshot` struct and the closed-enum `ActivityState`.
- Implement the schema-version branching with a single compiled-in `EXPECTED_STATE_SCHEMA_VERSION = 1`.
- Ensure tests pass. No more code than required to make them green.

## Refactor

- Extract the closed-enum `ActivityState` and `StateSnapshot` types into their own file (`apps/menubar/Sources/ActivityState.swift`) if the renderer ticket would benefit — but only if doing so doesn't expand scope.
- Confirm the unknown-state fallback path is implemented as "decode any unrecognized string as `.idle`" not as "throw and recover." Throwing-and-recovering on every unknown state is wasteful.
- Confirm error messages on `StateReadError` cases are useful enough that the renderer's tooltip code in P2.07 has the data it needs without re-parsing.

## Review Focus

- Closed enum on `ActivityState`: is unknown-state fallback implemented via `init(from:)` returning `.idle`, or via a separate normalization step? Either is acceptable; reviewer confirms it's intentional and tested.
- `EXPECTED_STATE_SCHEMA_VERSION` constant location and visibility — should be one-line and easy to grep when Phase 03 wants to bump it.
- Test coverage: are *all* P2.07 failure paths represented here so the renderer doesn't need to re-test parser failures?
- Public API shape — `Result<StateSnapshot, StateReadError>` vs. throws. Either fine; reviewer confirms it's consistent with what P2.07 needs.
- The Swift notes file: does it explain the *new* Swift concepts honestly, or does it pad with general Swift tutorial content? Tone check.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: each parsing case is a separate failing test before any implementation lands.
Why this path: closed-enum decoding with an `.idle` fallback for unknown strings is the smallest correct shape — it honors the contract doc's "closed enum, no string escape hatch" while still tolerating richer hook-emitted states without crashes.
Alternative considered: throwing on unknown state names and recovering at the renderer layer. Rejected because the renderer would then need to know about parsing internals.
Deferred: HP overlay decoding (Phase 05), source_event payload decoding (Phase 03 if needed for richer animation).
Contract note: this ticket consumes the forward-compat clause landed in P2.02; if any wording in the contract doc is ambiguous when implementing, record the ambiguity here and reopen P2.02 with a clarification.

Implementation notes (added during P2.03 delivery):

- `ActivityState` is a `String`-raw closed enum with an overridden `init(from:)` that maps any unknown raw string to `.idle`. Phase 02 only paints the four floor states; contract states beyond those (`reviewing`, `hyped`, `ascended`, etc.) decode as `.idle` rather than carry through, which is the contract-conformant "decode any unrecognized string as `.idle`" shape called out in Refactor.
- Schema-version policy is enforced *before* full `Decodable` decoding: a pre-pass via `JSONSerialization` reads `schema_version`, so `schemaMissingOrInvalid` and `schemaNewer(got:expected:)` are distinct from the generic `malformed` bucket — the renderer in P2.07 can pick the right tooltip without re-parsing.
- `EXPECTED_STATE_SCHEMA_VERSION = 1` lives as a single file-scope `let` in `StateJsonReader.swift` for a one-line bump surface in Phase 03.
- Public API uses `Result<StateSnapshot, StateReadError>` (not `throws`) so the renderer can pattern-match each failure case at the call site without `do/catch` ceremony, matching the ticket's stated preference for closed-enum-style switching.
- `notes/private/phase-02-swift-notes/` was un-ignored selectively in `.gitignore` (the rest of `notes/private/` stays ignored) so the swift-notes deliverable for P2.03–P2.10 can land in PRs as the phase plan requires without making the whole `notes/private/` tree tracked.
- Test fixtures live in `apps/menubar/Fixtures/state-json/` and are loaded via `#file`-relative paths rather than embedded in the test bundle's `Resources`. Adding `Fixtures` as a test-bundle resource is a future option if the test target moves out-of-tree, but for now the worktree layout is stable and the simpler `#file` traversal keeps the Xcode project config tighter.
