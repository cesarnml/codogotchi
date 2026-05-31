# P8.08 Developer tab — read-only observability

Size: 3 points
Type: feat
Scope: settings
Red: required

## Outcome

- The Developer tab pretty-prints the live `state.json` (with a refresh) and the `gate.json` sidecar (current gate, `since`, `expires_at`, and whether the gate is live or expired).
- It shows the **last 5** `state-transitions.log` entries (source kind / name / origin / state) — a light realtime tail, not full pagination.
- It shows the **renderer schema version vs `state.json` `schema_version`** and flags a mismatch (explains a gray pet without opening Finder); baseline is schema v4.
- It shows a per-platform **hooks-present** summary derived from the same logic as `hooks status --json`.
- It shows a **Cursor-bridge explainer**: last-seen `source_origin` / tool name + native-vs-Claude-bridge guidance, answering "why does my pet react in Cursor when `~/.cursor/hooks.json` is empty?" in-app.
- Everything is **read-only** — no writes from this tab.

## Red

- Test the last-5 tail returns the most recent 5 transitions in order and tolerates a shorter/empty log.
- Test the schema-mismatch flag: renderer version vs a `state.json` `schema_version` (equal → ok, differ → flagged).
- Test the hooks-present summary derives from the snapshot consistently with `hooks status --json`.
- Test the Cursor-bridge explainer surfaces the last-seen origin/tool from the transition log.
- Run the suite; confirm failure. Commit `[red]`.

## Green

- Wire `StateJsonReader`, `GateJsonReader`, `TransitionLog`, and `HooksStatusSnapshot` into a Developer view-model; render pretty JSON + the last-5 tail + version line + hooks summary + explainer text.

## Refactor

- Reuse the existing readers as-is; keep the view-model a thin read aggregation. Share the status formatter with the General tab if it diverges.

## Review Focus

- Strictly read-only — no accidental write paths (the log-verbosity write toggle is explicitly deferred).
- The last-5 tail and schema-mismatch are the load-bearing observability features (exit conditions) — verify against real fixtures.
- The Cursor explainer is the in-app answer to the empty-`hooks.json` question (exit condition 5) — confirm it reads real attribution, not static copy only.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: testLast5TailReturnsAtMost5Entries, testSchemaMismatchFlaggedWhenVersionsDiffer (all stubs returned empty/false/nil).
Why this path: the readers already exist (Phase 02/06/07); this is aggregation + presentation.
TransitionLogReader: implemented as `DeveloperTabViewModel.readLastNTransitions(_:from:)` (static) — reads NDJSON, skips heartbeat lines, returns last N in file order.
Alternative considered: full log pagination + verbosity toggle — deferred (write surface / scope).
Deferred: log-verbosity write toggle; full pagination; live polling (view refreshes on button press only for v1).
