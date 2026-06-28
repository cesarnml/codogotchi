# P12.03 Swift slice-directory reader + render

Size: 3 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `StateJsonReader` (or a renamed/added reader) scans the `state.d/` directory, decodes each slice as a `SliceEntry` (no top-level `schema_version` field — that is injected by `globalAggregate` on aggregation), and collapses the set to a single resolved state via a Swift `globalAggregate` reducer matching the TS tiebreak (most-recent `updated_at` wins).
- `EXPECTED_STATE_SCHEMA_VERSION` is bumped to `7` (intra-branch lockstep with P12.01's writer constant).
- The pet, menubar, and HUD render **identically to v1.1.1** for equivalent input (behavior-invisibility gate).
- `GateJsonReader` / gate-override precedence is reconciled against the new model: the ambient gate continues to override the **global-aggregate** resolved state. No change to `.son-of-anton`.
- Slices older than an mtime TTL are ignored by the reader (stale-slice reaping); a mid-write slice (tmp file) is never read as state.

## Red

- Write failing Swift tests (XCTest), behavior-first:
  - **Characterization (signature):** given single-session slice fixtures for representative inputs (idle, each activity_state, HP-overlay/dead, attention, tool_command), the reader+reducer resolves to the exact `ActivityState` (and overlay/attention) v1.1.1 produced from the equivalent `state.json`.
  - Multi-slice: two slices → `globalAggregate` resolves to the most-recent by `updated_at`.
  - Gate override still wins over the resolved aggregate when the gate is unexpired and has a sprite row.
  - Stale slice (mtime beyond TTL) is excluded from the reduction.
- Confirm failures; commit `test(P12.03): slice-directory reader characterization [red]` before implementing.

## Green

- Implement the directory scan + per-slice decode + `globalAggregate` collapse. Keep decode tolerant of extra fields (existing best-effort posture). Note: slice files carry no top-level `schema_version`; the refuse-newer clause (`EXPECTED_STATE_SCHEMA_VERSION == 7`) applies to the aggregated `StateJsonV1` output, not to individual slice files.
- Bump `EXPECTED_STATE_SCHEMA_VERSION` to 7.
- Reconcile `GateJsonReader` precedence to apply over the resolved aggregate state (the existing merge-precedence chain in `gate-json.md` applies to the aggregate, not a per-slice state).
- Apply mtime TTL filtering; ignore tmp/partial files by name pattern.

## Refactor

- If the reader file is renamed (`StateJsonReader` → e.g. `SliceDirReader`), update references and the Developer-tab schema-version surface (`DeveloperTabViewModel.rendererSchemaVersion`) — keep it reporting `EXPECTED_STATE_SCHEMA_VERSION`.
- Only touch what this ticket needs; do not do the Swift TODO art remaps (deferred).

## Review Focus

- **Behavior-invisibility is the gate** — the characterization tests are the evidence. A reviewer should be able to read them and believe the pet renders identically.
- Swift `globalAggregate` tiebreak must match the TS one (P12.01) exactly — divergence means CLI `status` and the pet could disagree.
- Gate precedence: confirm the gate still overrides correctly now that the underlying state is a reduction, not a single file read.
- TTL value choice + partial-write exclusion — does the 1 Hz poll ever catch a half-written directory? (tmp+rename should prevent it; verify the scan filters tmp names.)
- Confirm no Settings, no visible per-platform fan-out, no `.son-of-anton` edits.

## Rationale

**Why this path:** `SlicePayload` omits top-level `origin`/`sessionId` fields — the filename provides that keying metadata and the fields are unused by the reducer. This keeps old-format fixture files decodable as `SlicePayload` without requiring new fixtures, maintaining test coverage continuity.

**Alternative considered:** Storing `origin`/`sessionId` in `SlicePayload` for future logging. Deferred — unused fields add decoder brittleness with no current benefit.

**Deferred:** Renaming `StateJsonReader` → `SliceDirReader` (see Refactor section). The existing `read(at:)` path still exists for legacy compatibility; rename is a follow-up cleanup.

**Contract note:** LivePollingTests error-visual tests now inject custom `reader` closures rather than writing files that trigger parse errors. The directory reader uses best-effort slice decoding (malformed slices silently skipped), so `.malformed`/`.schemaNewer` errors can only arise from the legacy `read(at:)` path. Error-visual driver behavior is still covered; the test style reflects the reader contract accurately.
