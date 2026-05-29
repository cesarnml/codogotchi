# P7.01 Schema v4 vocabulary — 19-state enum, drop work_mode, row-map rename + placeholders

Size: 3 points
Type: feat
Scope: contracts
Red: required

## Outcome

- `ACTIVITY_STATES` in `packages/contracts/src/animation-state.ts` is the 19-state schema-v4 closed enum: `idle`, `standby`, `implementing`, `testing`, `thinking`, `reading`, `cramming`, `errored`, `waiting_for_input` (hook/lite/Codex) + `ticket_started`, `red_tdd`, `green_tdd`, `adversarial_review`, `open_pr`, `poll_review`, `record_review`, `advance`, `ticket_completed`, `review_clean` (SoA gates). The 12 deleted states (`hyped`, `celebrating`, `calling_for_backup`, `waiting`, `focused`, `nervous`, `panicking`, `ascended`, `reviewing`, `pushing`, `running-tests`, `requesting_input`) are gone.
- `STATE_JSON_SCHEMA_VERSION` is `4`; `state-json.ts` drops the `work_mode` field; no `gate_badge` field is added.
- Swift `ActivityState` (apps/menubar) has the 19 cases with correct `rawValue` strings; `EXPECTED_STATE_SCHEMA_VERSION = 4`.
- `CodogotchiPet.rowMap` keys are renamed to the surviving gate states (`review_clean`/`ticket_completed`→row 0, `ticket_started`→row 1, `adversarial_review`→row 5) and gain **temporary placeholder** rows: `green_tdd`→row 2, `red_tdd`→row 3, `open_pr`→row 4, `record_review`→row 8. A comment marks these as temporary pending `codogotchi-soa-spritesheet.webp`.
- All TS and Swift fixtures referencing old state names are updated to v4 names; the full suite (TS `bun test` + Swift `mac:test`) is green.
- `RELIABLE_ACTIVITY_STATES` / `HEURISTIC_ACTIVITY_STATES` groupings are updated to the v4 vocabulary (or removed if obsolete).

## Red

- TS: extend `animation-state` / `state-json` tests so they fail against the current enum — assert v4 names are members, deleted names are not, `parseStateJson` accepts `schema_version: 4` and rejects `5`, and a payload with a removed state (`hyped`) fails to parse.
- Swift: add an `ActivityState`/`StateJsonReader` test asserting the 19 cases decode and `EXPECTED_STATE_SCHEMA_VERSION == 4` (a v4 payload parses; a v5 payload yields `.schemaNewer`).
- Run both suites; confirm the new assertions fail.
- Commit `[red]`: `test(contracts): schema v4 19-state enum + version bump [red]`.

## Green

- Rewrite `ACTIVITY_STATES`, bump `STATE_JSON_SCHEMA_VERSION`, remove `work_mode` from the Zod schema, and retire stale groupings.
- Update Swift `ActivityState` cases + `EXPECTED_STATE_SCHEMA_VERSION`; rename `CodogotchiPet.rowMap` keys and add the temporary placeholder rows.
- Update every fixture (TS + Swift) to v4 names. Make both suites green with the smallest changes — no behavioral classifier or reader changes (those are P7.02/P7.04).

## Refactor

- Update the row-map doc comment in `CodogotchiPet.swift` to list the v4 mapping and flag placeholders as temporary with the target soa-sheet destination.
- Remove any now-dead enum-derived helpers; do not touch hook classification or the gate.json reader.

## Review Focus

- Enum membership exactly matches research §8's closed enum — no extra, no missing.
- Cross-language consistency: every TS state string has a matching Swift `rawValue`.
- `work_mode` is fully removed (schema + any reader/writer references) and no `gate_badge` field was introduced.
- Placeholder row mapping is correct (`green_tdd`→2, `red_tdd`→3, `open_pr`→4, `record_review`→8) and clearly marked temporary.

## Rationale

Red first: TS tests failed on `STATE_JSON_SCHEMA_VERSION` (3 ≠ 4) and enum membership checks for new v4 states. Swift tests failed on `EXPECTED_STATE_SCHEMA_VERSION` (3 ≠ 4) and `ActivityState(rawValue: "ticket_started")` returning nil.

Why this path: Atomic rename — enum, schema version, and all fixtures changed together. Hook-binary vocabulary names (`running-tests`→`testing`, `reviewing`→`thinking`, `pushing`→`implementing`, SoA gate states→v4) updated to compile with the new enum without changing behavioral classification logic; full behavioral rewrite is P7.02.

Alternative considered: Keeping old states as deprecated aliases alongside new states — rejected because the ticket spec explicitly calls for a closed 19-state enum with the 12 old states removed.

Deferred: New behavioral classification rules (`reading`/`cramming` streak, `thinking` explore bucket) — P7.02. Multi-sheet loader and dedicated gate art — later phase. `waiting_for_input` hook wiring — platform-hooks phase.

Contract note: CodexPet row 7 now maps to both `.implementing` and `.testing` (shared running loop — visual compromise until lite sheet ships). DemoCycleDriver cycle grew from 15 to 19 states to match the full v4 enum.
