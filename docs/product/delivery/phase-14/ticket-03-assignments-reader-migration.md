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

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
