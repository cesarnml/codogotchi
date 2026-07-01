# P15.01 Contracts: customization.json session-pets fields

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `CustomizationSnapshot` exposes two new per-platform fields: `sessionPetsEnabled: [String: Bool]` and `sessionCap: [String: Int]`.
- `CustomizationJsonReader` decodes `session_pets_enabled` and `session_cap` from `customization.json`, tolerating absence and malformed values with safe defaults (`[:]` / `[:]`).
- A `session_cap` value of `0` decodes as the Unlimited sentinel; negative or absent values for an enabled platform resolve to the default cap of `3` at the point of use (documented, not silently coerced in the reader).
- `customization.json` stays `schema_version: 1`; unknown/extra keys continue to decode without error, matching the existing forward/back-tolerant posture.
- `CustomizationSnapshot.safeDefault` includes the two new fields as empty maps, so the pool stays functional when the file is absent.

## Red

- Add `CustomizationJsonReaderTests` cases: (1) a file with `session_pets_enabled` + `session_cap` populated decodes the maps correctly; (2) an absent-both file yields empty maps; (3) a `session_cap` of `0` is preserved (Unlimited sentinel); (4) a malformed `session_pets_enabled` value degrades to the safe default without throwing.
- Run the suite and confirm the new cases fail against the current reader.
- Commit with suffix `[red]`: `test(P15.01): customization session-pets field decoding [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Extend `CustomizationPayload` with `sessionPetsEnabled: [String: Bool]?` and `sessionCap: [String: Int]?`.
- Extend `CustomizationSnapshot` and `.safeDefault`, and populate the two maps in `CustomizationJsonReader.read` (default to `[:]` when absent).
- Do not add cap-default resolution or Unlimited interpretation logic here beyond preserving `0` — consumers (P15.04/P15.07/P15.09) own the default-3 and Unlimited semantics.

## Refactor

- Only touch `CustomizationJsonReader.swift`, `PerPlatformSnapshot.swift`'s `CustomizationSnapshot`, and the test file. No pool or UI wiring in this ticket.

## Review Focus

- The two new fields are additive and default-empty — confirm no existing `CustomizationJsonReaderTests` case regresses and `schema_version` is untouched.
- Confirm `0` is preserved end-to-end (not clamped) so the Unlimited sentinel survives the decode.
- Verify the reader does not itself apply the default-3 — that belongs to consumers so the on-disk absence stays distinguishable from an explicit value.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: The four new `CustomizationJsonReaderTests` cases failed to compile because `CustomizationSnapshot` had no `sessionPetsEnabled` / `sessionCap` members — a compile-level red for a contract-only ticket.
Why this path: Added the two maps as plain `[String: Bool]` / `[String: Int]` optionals on `CustomizationPayload`, defaulting to `[:]` in `read`. This reuses the reader's existing "top-level decode failure ⇒ `safeDefault`" posture for malformed input (a malformed `session_pets_enabled` throws the whole decode and yields empty maps) rather than adding bespoke per-field lenient decoding the consumers don't need yet.
Alternative considered: Lenient per-field decoding (decode each map entry independently so one bad value doesn't drop the whole file). Rejected as premature — it adds surface area and diverges from the established whole-file `safeDefault` behavior; no consumer requires partial survival of a corrupt file this phase.
Deferred: Default-3 resolution and the Unlimited (`0`) interpretation stay with consumers (P15.04/P15.07/P15.09); the reader only preserves `0` verbatim.
Contract note: The ticket's Refactor section names "`PerPlatformSnapshot.swift`'s `CustomizationSnapshot`", but `CustomizationSnapshot` actually lives in `CustomizationJsonReader.swift` (no reference in `PerPlatformSnapshot.swift`). Only `CustomizationJsonReader.swift` and the test file were touched, plus the phase CI-baseline record in `implementation-plan.md`.
Subagent review: Advisory pass (claude-cli) returned no actionable findings. Two low-cost advisory test-hardening observations were applied to lock this contract before downstream tickets build on it — the malformed test now also asserts `sessionCap == [:]`, and a new case asserts a negative `session_cap` passes through verbatim (no reader clamp). A third advisory observation — surfacing a "settings file invalid" signal for human-edited `customization.json` — is genuinely P15.09 (Settings UI) scope and stays advisory for `/soa tao`.
