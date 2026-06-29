# P14.03 Swift: AssignmentsJsonReader + writer + migration seed

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A Swift `AssignmentsJsonReader` reads `~/.codogotchi/assignments.json` and returns an `AssignmentsSnapshot` with a safe default (`default = "maew"`, no platform overrides) on any IO/decode failure.
- `AssignmentsSnapshot.resolve(origin:)` returns the override petId for an origin, or the `default` petId when the origin has no override (and for `combined`).
- A writer persists assignments through the existing persist-first `ConfigFileWriter` pattern, enforcing the uniqueness invariant: assigning a badge (platform key or `default`) to a new pet removes that badge from any pet that previously held it.
- A one-time idempotent migration seeds `assignments.json` when absent: raw-read `config.json`'s `pet` key (schema-independent `JSONSerialization`, fallback `maew`) into `default`, write the file, and never read `config.pet` again.
- Re-running the migration when `assignments.json` already exists is a no-op (does not overwrite user assignments).

## Red

- Add `AssignmentsJsonReaderTests`: malformed/absent file → safe default; full file resolves overrides; an origin without an override resolves to `default`; `combined` resolves to `default`.
- Add writer tests: assigning `claude_code` to pet B when pet A held it removes it from A; reassigning `default` moves it; result round-trips through the reader.
- Add migration tests: absent `assignments.json` + `config.json` with `pet: "foo"` seeds `default: "foo"`; absent both → `default: "maew"`; existing `assignments.json` is left untouched (idempotent).
- Run `swift test` (or `bun run mac:test`) and confirm failures.
- Commit with suffix `[red]`: `test(menubar): assignments reader + migration [red]`.

## Green

- Add `AssignmentsJsonReader.swift` mirroring `CustomizationJsonReader.swift` (Decodable payload, snake_case strategy, safe-default fallback).
- Add the writer routed through `ConfigFileWriter`, enforcing uniqueness before persist.
- Add the migration seed; call site wiring into app launch happens in P14.05 (or here behind a function the app calls) — keep the seed function pure/injectable for tests.

## Refactor

- Factor the badge-uniqueness logic into a small pure function so the writer and P14.07's view model can share it.
- This ticket adds a new tracked config file but does not move tracked files — no `soa-sync.sh` migration function needed.

## Review Focus

- Uniqueness invariant correctness: every badge ends up on exactly one pet after any assignment.
- Migration idempotency and the raw-read of `config.pet` (must not depend on the now-removed TS schema key).
- Safe-default behavior parity with `CustomizationJsonReader` (never throw to the pool).

## Rationale

Red first: `testValidFileDecodesAllFields` — `platformOverrides["claude_code"]` was nil because
`keyDecodingStrategy = .convertFromSnakeCase` conflicts with explicit `CodingKeys`. When both are
present, the decoder converts the JSON key from snake_case before matching against `CodingKey.stringValue`,
causing explicit snake_case raw values to never match. Fix: remove `convertFromSnakeCase` and rely
solely on the explicit CodingKeys enum which already maps to the correct JSON key names.

Why this path: `AssignmentsPayload` with explicit `CodingKeys` handles the `"default"` JSON key
cleanly without backtick property names in the struct. `platformOverrides` stores only the 5 optional
platform keys, keeping the snapshot API compact and `resolve(origin:)` trivial.

Alternative considered: Using `JSONSerialization` directly instead of `Decodable`. Rejected because
`Decodable` gives type safety and aligns with `CustomizationJsonReader`'s pattern; the only special
case (`"default"` key) is handled cleanly via CodingKeys.

Deferred: Enforcement that `badge` is one of the 6 valid keys is not done in `AssignmentsJsonWriter.write` —
the `ASSIGNMENT_BADGE_KEYS` constant is exported for callers. P14.07's ViewModel enforces this in the UI layer.

Contract note: `applyBadgeAssignment(badge:petId:in:)` is a free function (not a method on
`AssignmentsJsonWriter`) so P14.07's ViewModel can use it without depending on the URL-based writer API.

Subagent review patches (2026-06-29):

Finding 1 — fresh non-default badge write: `AssignmentsJsonWriter.write(badge:petId:to:)` called with a
non-default badge on a fresh URL previously produced a file with no `default` key; the reader returned
`safeDefault` and silently dropped the just-written assignment. Fix: when badge != "default" and the file
is absent, the merge dict is augmented with `"default": DEFAULT_PET_NAME` so the reader always decodes
a valid snapshot.

Finding 2 — migration TOCTOU race: `seedIfAbsent` replaced the `fileExists` + `ConfigFileWriter.merge`
two-step with O_EXCL exclusive-create semantics via `Darwin.open`. `O_CREAT | O_EXCL` fails atomically
with EEXIST when another process wins the race; the caller treats that as a no-op, matching the idempotency
contract without risking a silent overwrite of a concurrently-created file.

Green section note: the "snake_case strategy" phrase in the Green checklist is stale; it was written before
the convertFromSnakeCase conflict was discovered. The appended Rationale (above) documents the actual approach.
