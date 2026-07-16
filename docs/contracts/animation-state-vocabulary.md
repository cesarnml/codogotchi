# Animation State Vocabulary (v10)

The contract for the data the codogotchi hook binary writes to
`~/.codogotchi/state.d/<origin>:<session_id>.json` on every relevant Claude Code / Codex / Cursor lifecycle event,
and which any future renderer (macOS app, web preview, CLI ascii) consumes.

This doc defines the **closed enums** of activity states and HP overlay states,
the v7 slice-directory model (`state.d/<origin>:<session_id>.json`, no `schema_version` in the on-disk slice file), and the mapping table from
raw signal classes to activity states. Closed enums mean a renderer can switch
exhaustively without a `default:` catch-all; adding a state is a deliberate
schema bump, not a runtime surprise.

Nothing in Phase 01 consumes these types beyond the schema itself. They are
foundation contracts for:

- **P1.06** Convex schema's `mood` field
- **P1.18** Hook binary (the writer of `state.json`)
- **P1.19** SoA gate signal mapping

## Revision policy

This contract is intentionally locked early. **P1.18 (Hook binary) is allowed
exactly one revision** if hook-side implementation reveals an honest mismatch
between the planned vocabulary and observable lifecycle events. Any revision:

- bumps `schema_version` to `2` and documents the migration here
- is recorded in P1.18's `## Rationale` section
- preserves the closed-enum discipline (no `string` escape hatches)

After P1.18 lands, further changes require a new ticket and a separate
schema-version bump.

Phase 03 (P3.01) is the formal v2 bump: it appended `requesting_input` and
`errored` to the activity-state enum and raised `STATE_JSON_SCHEMA_VERSION` from
1 to 2.

Phase 06 (P6.01) is the formal v3 bump: it renames `requesting_input` to
`standby` and raises `STATE_JSON_SCHEMA_VERSION` to 3. Three optional fields are
added: `attention` (object), `tool_command` (string), and `work_mode` (enum stub, later removed).

Phase 07 (P7.01) is the formal v4 bump: it replaces the 15-state enum with the 19-state
closed schema-v4 enum, removes the `work_mode` field, and locks the 6-tier animation
model described in §7 of `notes/public/phase-06-animation-and-signal-research.md`.
The hook binary becomes a pure platform-event classifier (no `.soa/events.ndjson` reads);
gate signals are delivered via `~/.codogotchi/gate.json` instead
(see `docs/contracts/gate-json.md`).

Phase 10 (P10.03 / P10.05) is the formal v5 bump for **local RPG**: when
`features.rpg_enabled` is true, the hook writer emits `schema_version: 5` with
`level`, `level_fraction`, `half_hearts`, and `last_activity_at`. Renderers accept
v4 payloads unchanged; v5 fields are required only when `schema_version >= 5`.
Swift applies local decay to `half_hearts` from `last_activity_at`; XP/heal are
owned by the CLI writer, not recomputed in the renderer.

The **v6 bump** adds the optional `revive_until` field: an ISO-8601 datetime
string set to `now + 5 s` whenever a hook write detects a half-heart gain
(`newHalfHearts > prevHalfHearts`). Renderers that understand v6 show the Tier 2
`revive` row (row 0) while `Date.now() < Date.parse(revive_until)`, then fall
through to the Codex idle row. Renderers that don't understand v6 refuse the
payload per the forward-compat policy. `revive_until` is absent (not `null`)
when no health gain occurred; renderers treat absence as "no revive animation".

**Phase 12 (P12.01–03) is the v7 bump:** the hook binary switches from writing a single
`~/.codogotchi/state.json` file to writing per-`(origin, session_id)` **slice files** in
`~/.codogotchi/state.d/<origin>:<session_id>.json`. The renderer scans the directory,
decodes each file as a `SliceEntry` (see § v7 slice-entry shape below), applies the
`globalAggregate` reducer (most-recent `updated_at` wins), and resolves a single
`StateSnapshot`/`StateJsonV1` with `schema_version: 7`. Key properties:

- On-disk slice files carry **no `schema_version` field** — versioning lives in the writer/reader constants (`STATE_JSON_SCHEMA_VERSION = 7` in TS, `EXPECTED_STATE_SCHEMA_VERSION = 7` in Swift).
- The reader ignores slices whose filesystem mtime is more than 2 hours old (stale-slice TTL). `SessionEnd` events delete the slice for the ending origin+session (best-effort).
- Temporary files matching `*.tmp-*` are never decoded.
- An empty `state.d/` directory (all slices stale, missing, or temporary) resolves to a synthetic idle default with `schema_version: 7`.
- The `perPlatform` reducer exists as a pure, unit-tested function but is **not wired to any renderer** in Phase 12. It is the foundation for v3 multi-pet rendering (wired in Phase 13).
- `gate.json` overrides the **global-aggregate resolved state** (Option 2 / ambient gate). Per-session gate stamping (`origin, session_id` in the gate file) is deferred to the v3 per-thread phase. See `gate-json.md`.

**Phase 13 (P13.01–07) is the v8 bump:** slices become pure **activity-signal files** — RPG fields (`level`, `level_fraction`, `hp`, `half_hearts`, `hp_overlay`, `last_activity_at`) are extracted to a separate `~/.codogotchi/rpg-state.json` file. The `perPlatform` reducer is wired to render: the Swift app spawns one independent `FloatingPetWindowPool` entry per active platform origin, each driving its own floating window. Key v8 properties:

- Slice files carry `schema_version: 8` and drop RPG fields. They contain only activity-signal fields: `origin`, `session_id`, `activity_state`, `source_event`, `updated_at`, and optionally `pid` (for CLI-origin liveness checks).
- `~/.codogotchi/rpg-state.json` is the single source of truth for all RPG values; all floating windows share the same RPG model.
- `~/.codogotchi/customization.json` controls per-platform display mode (`"own"` / `"combined"` / `"off"`) and idle-dismiss TTL. See `docs/contracts/customization-json.md`.
- The `perPlatform` reducer is the live render path for platforms in `"own"` mode; `globalAggregate` is used only for platforms in `"combined"` mode.
- `EXPECTED_STATE_SCHEMA_VERSION = 8` in Swift; `STATE_JSON_SCHEMA_VERSION = 8` in TS CLI.
- The macOS app is v2.0.0 as of Phase 13. The menubar icon is now a static app icon (no per-tick animation); all animation is in the floating panels.
- Renderers that expect v7 or lower will gray out on v8 slices (forward-compat policy: refuse higher versions).

**v9 removes `hp`/`hp_overlay` from both the slice-entry shape and the resolved `StateJsonV1` shape.** They were pure denormalization: the hook binary read `profile.json` on every write and stamped a copy of `hp`/`hp_overlay` into the slice, but no renderer (the Swift menu-bar app) ever decoded those keys off a slice or `state.json` — the pet's HP-driven visuals come from `~/.codogotchi/rpg-state.json`'s `half_hearts`, and `codogotchi status` now reads `hp`/`mood` directly from the profile cache instead of from the aggregated slice. Key v9 properties:

- Slice files carry only `origin`, `session_id`, `activity_state`, `source_event`, `updated_at`, and the optional `attention`/`tool_command`/`pid` fields. `hp`/`hp_overlay` are no longer valid keys — `sliceEntrySchema` is `.strict()` and rejects them.
- `StateJsonV1` keeps `hp`/`hp_overlay` as `.optional()` (not removed) so v1–v8 payloads written by an older hook binary still parse under the forward-compat policy; `globalAggregate`/`perPlatform` never populate them on the resolved shape.
- `EXPECTED_STATE_SCHEMA_VERSION = 9` in Swift; `STATE_JSON_SCHEMA_VERSION = 9` in TS CLI.

**Phase 20 (P20.01–04) is the v10 bump: four optional sticky ISO-8601 timestamps
land on the slice** so the PromptTimer chip and Settings > Sessions can show
correct elapsed/started time across window hide/show, TTL dismiss, fold
churn, and app relaunch — durability that in-memory trackers keyed off
`updated_at` cannot provide, since `updated_at` advances on every mid-turn
tool write and any in-memory tracker is lost when a render key leaves TTL
eligibility. Key v10 properties:

- Four new optional fields: `prompt_started_at`, `session_started_at`,
  `errored_since`, `turn_ended_at` — all `.datetime({ offset: true })`,
  i.e. ISO-8601 with an explicit UTC/offset designator. `sliceEntrySchema`
  stays `.strict()`; no other keys are added.
- The hook binary **read-merges** prior sticky stamps on every write (via
  `mergeStickyStamps` in `packages/cli/src/hook-binary.ts`) instead of
  rebuilding the slice from scratch — mid-turn tool ticks preserve whatever
  turn-start and session-birth stamps are already on disk.
- If the prior on-disk slice is unreadable (corrupt JSON, truncated file, a
  non-object payload, or a stamp value that isn't a valid offset-datetime
  string), the hook **fails closed**: it aborts that write entirely rather
  than persisting freshly-reset clocks over a damaged slice. A missing file
  (first write for that origin+session) is not corruption — that's the
  session-birth case below.
- `EXPECTED_STATE_SCHEMA_VERSION = 10` in Swift; `STATE_JSON_SCHEMA_VERSION = 10` in TS CLI.

#### Set/clear semantics (product level)

These are the only lifecycle edges allowed to set or clear a sticky stamp;
every other write (mid-turn tool use, unrecognized events) preserves
whatever is already on disk:

- **Mid-turn tool writes preserve turn-start and session-birth.** A tool-use
  event in the middle of a turn never rewrites `prompt_started_at` or
  `session_started_at` — it just carries the prior stamps forward untouched.
- **`prompt_submit` / `session_start` refresh `prompt_started_at`** to the
  current write time, and **clear `turn_ended_at`** and **clear
  `errored_since`** — a new turn starting means any prior freeze is over.
- **First create sets `session_started_at`.** The first write of a given
  `state.d/<origin>:<session_id>.json` slice stamps `session_started_at` to
  that write's timestamp; every later write preserves it unless a genuinely
  new session file is created (a different `session_id`).
- **First `errored` sets `errored_since` once.** Entering the `errored`
  activity state stamps `errored_since` only if it isn't already set —
  repeated `errored` writes for the same failure streak do not push the
  clock forward.
- **`standby` + attention sets `turn_ended_at`** (once, same
  set-only-if-absent rule as `errored_since`) — this is the hook's signal
  that the turn cleanly finished and is now waiting on the developer.
- **Idle / Force Idle clears turn clocks, preserves `session_started_at`.**
  Any write that resolves to the `idle` activity state — including the
  menubar's Force Idle / dismiss-attention idle rewrite — clears
  `prompt_started_at`, `errored_since`, and `turn_ended_at`, but leaves
  `session_started_at` alone; going idle ends the current turn, not the
  session.
- **Errored freeze duration is app-side math, not a hook-written stamp.**
  The renderer computes the errored freeze window as `errored_since + 60s`
  (the same 60-second grace the PromptTimer already used pre-v10). The
  menubar does **not** write `turn_ended_at` when that 60-second threshold
  elapses — `turn_ended_at` remains exclusively hook-owned, set only on
  clean `standby` + attention. This keeps the contract single-writer: the
  hook is the only process that stamps slice files.

### Current on-disk slice shape (v10)

The § Resolved state shape, § v7 slice-entry shape, and § v9 slice shape
(historical) sections below are kept for historical reference (each
documents the shape at the version it was written) — this section is the
authoritative current shape. A v10 slice file
(`state.d/<origin>:<session_id>.json`) is:

```json
{
  "origin": "claude_code",
  "session_id": "sess-abc123",
  "activity_state": "testing",
  "updated_at": "2026-06-03T04:00:01.000Z",
  "source_event": {
    "origin": "claude_code",
    "kind": "tool_use",
    "name": "Bash"
  },
  "tool_command": "bun test packages/contracts",
  "prompt_started_at": "2026-06-03T03:59:40.000Z",
  "session_started_at": "2026-06-03T03:50:00.000Z"
}
```

Required fields: `origin`, `session_id`, `activity_state`, `updated_at`,
`source_event`. `attention`, `tool_command`, `prompt_started_at`,
`session_started_at`, `errored_since`, and `turn_ended_at` are optional.
`hp`, `hp_overlay`, `level`, `level_fraction`, `half_hearts`,
`last_activity_at`, and `revive_until` are **not** valid slice keys —
`sliceEntrySchema` is `.strict()` and rejects them. RPG values live in
`~/.codogotchi/rpg-state.json`; HP/mood live in `~/.codogotchi/profile.json`.

#### v9 slice shape (historical)

> Historical: documents the shape as of v9, before the Phase 20 sticky-stamp
> bump. See § Current on-disk slice shape (v10) above for what the schema
> requires today.

A v9 slice file (`state.d/<origin>:<session_id>.json`) was:

```json
{
  "origin": "claude_code",
  "session_id": "sess-abc123",
  "activity_state": "testing",
  "updated_at": "2026-06-03T04:00:01.000Z",
  "source_event": {
    "origin": "claude_code",
    "kind": "tool_use",
    "name": "Bash"
  },
  "tool_command": "bun test packages/contracts"
}
```

Required fields: `origin`, `session_id`, `activity_state`, `updated_at`,
`source_event`. `attention` and `tool_command` were the only optional
fields prior to the v10 sticky-stamp bump.

### Forward-compatibility policy

Renderers are the lagging consumers of this contract. The hook binary is
allowed to ship a newer `schema_version` than the renderer expects (e.g., a
user updates `codogotchi-hook` but has not yet updated the macOS menu-bar
app), but the renderer is **not** allowed to silently misinterpret a payload
it does not understand. The policy:

- Renderers **MUST accept** any payload whose `schema_version` is less than or
  equal to the renderer's `EXPECTED_VERSION`. Parse best-effort: read the
  fields defined for that older version and ignore any extra fields the
  payload may carry.
- Renderers **MUST refuse** any payload whose `schema_version` is greater than
  the renderer's `EXPECTED_VERSION`. Treat this as a hard failure and surface
  it as a desaturated visual or equivalent error mode — never guess at the
  newer shape.
- Adding a new **optional** field to a future schema version does not require
  a `schema_version` bump. Changing the meaning of an existing field, removing
  a field, or narrowing a field's domain (including the closed enums) **does**
  require a bump.
- A payload with a missing or non-integer `schema_version` is treated the same
  as an unsupported version: refuse and surface the failure visual.

Rationale: an older hook on a newer renderer should keep working, because the
renderer already knows every field the older hook can produce. A newer hook on
an older renderer must force a renderer update rather than silently degrade —
the renderer cannot distinguish a benign added field from a changed-meaning
field without explicit version discipline. The asymmetry runs in one
direction: renderers tolerate older payloads; renderers refuse newer payloads.

### Renderer tooltip copy

These are the canonical user-facing tooltip strings Phase 02's menu-bar app
will display when the forward-compat policy refuses a payload. The contract
doc is the source of truth for the wording; renderers must reproduce these
strings character-for-character (substituting the placeholders).

- Polling target absent (the `~/.codogotchi/state.d/` directory does not
  exist on disk — almost certainly because the hook binary is not installed
  or has never run):
  - `codogotchi-hook not detected`
- Missing or non-integer `schema_version`, **or** malformed JSON that cannot
  be parsed as an object (both fold to the same user-facing copy — the
  distinction is not actionable for non-developer users). Note: these error
  paths are only reachable via the legacy `StateJsonReader.read(at:)` path;
  the v7 directory reader uses best-effort slice decoding (malformed slices
  silently skipped):
  - `state.json schema_version is missing — codogotchi-hook may be too old.`
- Newer-than-expected `schema_version` (with `{got}` = observed value,
  `{expected}` = renderer's `EXPECTED_VERSION`). Same caveat as above — only
  via the legacy read path:
  - `state.json schema_version is v{got}; this app supports v{expected}. Update the menu bar app.`

## Activity States (v4 closed enum — 19 states)

States marked **v2** required the v2 schema bump; **v3** v3 bump; **v4** v4 bump.
The 12 states removed in v4 (`hyped`, `celebrating`, `calling_for_backup`, `waiting`,
`focused`, `nervous`, `panicking`, `ascended`, `reviewing`, `pushing`, `running-tests`,
`requesting_input`) are no longer valid; a renderer that sees them in an old payload
decodes them as `idle`.

### Hook states (written by `codogotchi-hook`)

| State             | Ver | Meaning                                                      | Source signal class                                                                    | Reliability |
| ----------------- | --- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------- | ----------- |
| `idle`            | v1  | No active session or no recent activity.                     | Missing `state.json` baseline; renderer quiet default.                               | reliable    |
| `standby`         | v3  | Pet is waiting for the developer.                            | `Stop` (success) / Cursor `stop` (no error) / Codex `SessionEnd`.                     | reliable    |
| `errored`         | v2  | Pet is distressed — agent failed.                            | `StopFailure`; `Stop` + `stop_reason: max_tokens`; Cursor `stop` + `status: error`; Cursor `postToolUseFailure` (non-interrupt). | reliable    |
| `waiting_for_input` | v4 | Pet is awaiting a permission prompt.                         | `PermissionRequest` — wiring deferred to platform-hooks phase. Reserved enum entry.   | reliable    |
| `implementing`    | v1  | Pet is writing code.                                         | `Edit`, `Write`, `MultiEdit`, `apply_patch`; unknown/write Bash/Shell commands.        | heuristic   |
| `testing`         | v4  | Pet is running tests / verification work.                    | Bash/Shell commands matching test/format/lint/typecheck/build runners (incl. `bun run ci`, `verify:quiet`, `format`, `typecheck`, `mac:test`, `xcodebuild ... build/test`). | heuristic   |
| `thinking`        | v4  | Pet is exploring/searching the codebase.                     | `Grep`/`Glob`; Bash/Shell read/search commands (incl. compound `&&`/`;` chains); `prompt_submit`; unrecognized hook events. | heuristic   |
| `reading`         | v4  | Pet is reading source files (light streak).                  | `Read` tool-use ×1–2; `ToolSearch`, `Skill`, `WebSearch`/`WebFetch`/`SemanticSearch`; `mcp__*` tools. | heuristic   |
| `cramming`        | v4  | Pet is deep-reading (heavy streak).                          | `Read` tool-use ×3+ in a row without an intervening write.                             | heuristic   |

### SoA gate states (rendered via `gate.json` sidecar, written by son-of-anton Phase 17)

| State              | Ver | Meaning                                           | gate.json `gate` value  | Sprite row (codogotchi sheet) |
| ------------------ | --- | ------------------------------------------------- | ----------------------- | ----------------------------- |
| `ticket_started`   | v4  | Delivery ticket just started.                     | `ticket_started`        | 1 (permanent) |
| `red_tdd`          | v4  | Failing test committed.                           | `red_tdd`               | 3 (TEMP placeholder) |
| `green_tdd`        | v4  | Tests passing.                                    | `green_tdd`             | 2 (TEMP placeholder) |
| `adversarial_review` | v4 | Subagent review in progress.                     | `adversarial_review`    | 5 (permanent) |
| `open_pr`          | v4  | PR opened for review.                             | `open_pr`               | 4 (TEMP placeholder) |
| `poll_review`      | v4  | AI review window open.                            | `poll_review`           | none — falls to hook |
| `record_review`    | v4  | Review outcome recorded.                          | `record_review`         | 8 (TEMP placeholder) |
| `advance`          | v4  | Phase/ticket advanced.                            | `advance`               | none — falls to hook |
| `ticket_completed` | v4  | Ticket marked done.                               | `ticket_completed`      | 0 (shared, permanent) |
| `review_clean`     | v4  | Review recorded as clean.                         | `review_clean`          | 0 (shared, permanent) |

Temporary placeholder rows repurpose existing Codex sheet art until
`codogotchi-soa-spritesheet.webp` ships. See `docs/contracts/gate-json.md`
for the full precedence rules and per-gate row assignments.

`reliable` states come from explicit lifecycle signals (Stop events, StopFailure, gate.json).
`heuristic` states are inferred from raw tool-use stream patterns; best-effort.

The mapping is single-writer: the hook binary classifies and writes one state per event.
The renderer merges the hook state with the gate.json sidecar state using the resolver
in `GateJsonReader.swift` (gate wins when unexpired + has art; else hook state shows through).

## HP Overlay States (closed enum)

The HP overlay is orthogonal to activity state. A pet can be `implementing`
*and* `near_death` at the same time — the renderer composes the two. Buckets:

| Overlay        | HP range          | Meaning                                          |
| -------------- | ----------------- | ------------------------------------------------ |
| `thriving`     | `HP > 75`         | Healthy. No visual distress.                     |
| `getting_sick` | `25 < HP ≤ 75`    | Mild distress. Soft visual cue (color, droop).   |
| `near_death`   | `0 < HP ≤ 25`     | Heavy distress. Strong visual cue (sweat, gasp). |
| `ghost`        | `HP ≤ 0`          | Dead. Renderer shows ghost form until revived.   |

HP is server-canonical and computed in Convex's `syncProfile` mutation. As of
v9 the hook binary no longer reads or forwards HP at all — it writes only the
activity state to the slice. `~/.codogotchi/profile.json` (the local cache of
the last sync response) is the sole place HP/mood are carried on disk;
`codogotchi status` reads `hp`/`mood` from that cache directly. HP bucket
boundaries are confirmed by the engine implementation in **P1.04** — if P1.04
discovers a more honest curve (e.g. half-life decay around 50), it updates this
table and bumps `schema_version`.

## Resolved state shape (v7)

> Historical: documents the shape as of v7. See § Current on-disk slice shape (v10) above for what the schema requires today.

The renderer collapses `state.d/` slices via `globalAggregate` into a `StateJsonV1` object with `schema_version: 7`. This is the shape the renderer operates on internally — it is not written to disk as a single file. The on-disk format is the slice-entry shape above.

Resolved state schema (output of `globalAggregate`):

```json
{
  "schema_version": 7,
  "activity_state": "testing",
  "hp_overlay": "thriving",
  "hp": 87,
  "level": 12,
  "level_fraction": 0.42,
  "half_hearts": 5,
  "last_activity_at": "2026-06-03T04:00:00.000Z",
  "updated_at": "2026-06-03T04:00:01.000Z",
  "revive_until": "2026-06-03T04:00:06.000Z",
  "source_event": {
    "origin": "claude_code",
    "kind": "tool_use",
    "name": "Bash"
  },
  "tool_command": "bun test packages/contracts"
}
```

v6 changes from v5:

- `revive_until` — optional ISO-8601 datetime. Present when the hook detected a half-heart gain on this write (`newHalfHearts > prevHalfHearts`); set to `now + 5 s`. Absent when no gain occurred. Renderer shows the Tier 2 `revive` row (row 0) while `Date.now() < Date.parse(revive_until)`.

v5 changes from v4 (local RPG only — writer emits v4 when `rpg_enabled` is false):

- `level` — integer `1..100` from cumulative lifetime tokens (`levelForXp`).
- `level_fraction` — number `0..1`, progress within the current level toward the next.
- `half_hearts` — integer `0..6` (three hearts × two half-hearts); canonical HP unit for the floating HUD; Swift may decrement locally for idle decay.
- `last_activity_at` — ISO-8601 timestamp of last coding activity across hooked platforms, or `null` before first activity.

v4 changes from v3:
- `activity_state` uses the v4 19-state enum (old states like `running-tests`,
  `reviewing`, `pushing`, `hyped`, etc. are removed).
- `work_mode` field is **removed** — the information it carried is now expressed
  by the v4 activity states (`testing`, `thinking`, `implementing`).
- `gate_badge` field was never added (deferred; gate signals use `gate.json` instead).
- `attention` and `tool_command` optional fields are unchanged.

Per the forward-compat policy, v1–v4 payloads continue to parse when the renderer's
`EXPECTED_VERSION` is 5 (`got ≤ expected`). Old activity_state values from removed states
decode as `idle` in the Swift renderer (unknown-rawValue fallback). Payloads with
`schema_version > EXPECTED_VERSION` are refused.

### Field meanings

- `schema_version` — integer, starts at `1`. Future revisions bump this rather
  than silently mutating shape. Renderers branch on this and refuse unknown
  versions instead of guessing.
- `activity_state` — one of the closed activity-state enum values.
- `hp_overlay` — one of the closed HP-overlay enum values. Always derived from
  the most recently observed `hp` value; the hook does not compute it on the
  fly, it carries forward the bucket the last sync produced.
- `hp` — integer `[-100, 100]`. Legacy sync bucket; local RPG HUD uses `half_hearts`
  for hearts display. Below zero is permitted to model "ghost depth"; the renderer
  treats anything ≤ 0 as `ghost` for overlay tinting.
- `level`, `level_fraction`, `half_hearts`, `last_activity_at` — v5 RPG fields;
  see v5 example above. Required when `schema_version >= 5`.
- `updated_at` — ISO-8601 timestamp of when the hook wrote this state.
- `source_event` — the event that caused this write. Renderers may use this
  for short transition animations.
  - `origin` — closed enum: `claude_code` | `codex` | `soa` | `sync` | `manual`.
  - `kind` — closed enum: `tool_use` | `session_start` | `session_end` | `gate` | `sync_response` | `cli`.
  - `name` — free-form string for the originating event (`Edit`, `git push`,
    `ticket_started`, etc.). Closed-enum discipline applies to `origin` and
    `kind`; `name` is intentionally open to keep new tools / gates from
    requiring a schema bump.

### File location

**v7 (Phase 12+):** slice directory model

- Slice directory: `~/.codogotchi/state.d/`
- Per-session slice file: `~/.codogotchi/state.d/<origin>:<session_id>.json`
  - `<origin>` — `SourceEventOrigin` raw value (e.g. `claude_code`, `codex`, `cursor`)
  - `<session_id>` — session identifier string, no path separators, defaults to `"default"` when the platform has no stable session ID
- Test override: `$CODOGOTCHI_HOME/state.d/` when the env var is set

The hook binary creates `state.d/` with `mkdir -p` on first write. Readers must treat a missing or empty `state.d/` as the idle baseline.

**v6 and earlier:** single-file model (legacy, removed in v7 within the branch)

- `~/.codogotchi/state.json`

### v7 slice-entry shape (`state.d/<origin>:<session_id>.json`)

> Historical: documents the shape as of v7 (before the v8 RPG-field extraction and the v9 hp/hp_overlay removal). See § Current on-disk slice shape (v10) above.

Each slice file is a JSON object validated against `sliceEntrySchema` in `packages/contracts/src/slice-entry.ts`. The file has **no `schema_version` field** — versioning is implicit in the writer/reader constants.

```json
{
  "origin": "claude_code",
  "session_id": "sess-abc123",
  "activity_state": "testing",
  "hp_overlay": "thriving",
  "hp": 87,
  "level": 12,
  "level_fraction": 0.42,
  "half_hearts": 5,
  "active_minutes": 3,
  "last_activity_at": "2026-06-03T04:00:00.000Z",
  "updated_at": "2026-06-03T04:00:01.000Z",
  "revive_until": "2026-06-03T04:00:06.000Z",
  "source_event": {
    "origin": "claude_code",
    "kind": "tool_use",
    "name": "Bash"
  },
  "tool_command": "bun test packages/contracts"
}
```

Required fields: `origin`, `session_id`, `activity_state`, `hp_overlay`, `hp`, `updated_at`, `source_event`. All v5 RPG fields (`level`, `level_fraction`, `half_hearts`, `last_activity_at`) are required when the slice comes from an RPG-enabled session; optional otherwise.

## Mapping Table (raw signal → activity state) — v4

This is the canonical mapping consumed by the hook binary (v4). When two rules
could apply, the earlier row wins.

| Source signal                                                                               | activity_state     |
| ------------------------------------------------------------------------------------------- | ------------------ |
| `StopFailure` hook event (any error value)                                                  | `errored`          |
| Cursor `postToolUseFailure` with `is_interrupt: false` (or absent)                          | `errored`          |
| `PostToolUseFailure` / Cursor `postToolUseFailure` with `is_interrupt: true`                | `idle`             |
| Cursor `stop` with `status: aborted` / `canceled` / `cancelled`                             | `idle`             |
| Copilot `sessionEnd` with `reason: abort` / `user_exit`                                     | `idle`             |
| `Stop` / Cursor `stop` with `is_error: true`, `stop_reason: max_tokens`, or `status: error`| `errored`          |
| `Stop` (success) / Cursor `stop` (success)                                                  | `standby`          |
| `UserPromptSubmit` / Cursor `beforeSubmitPrompt` / Codex `user_prompt_submit`               | `thinking`         |
| Edit / Write / MultiEdit / `apply_patch` tool-use (incl. Codex `postToolUse` + `name`)      | `implementing`     |
| `Grep` / `Glob` tool-use                                                                    | `thinking`         |
| `ToolSearch`, `Skill`, `WebSearch`, `WebFetch`, `SemanticSearch`, `mcp__*` tool-use       | `reading`          |
| Bash/Shell command matching a test/format/lint/typecheck/build runner (any `&&` / `;` segment) | `testing`       |
| Bash/Shell read/search command (prefix or segment: grep, rg, find, ls, cat, sed -n, git status, git log, git diff, …) | `thinking` |
| `Read` tool-use ×1 or ×2 (streak, no intervening write)                                    | `reading`          |
| `Read` tool-use ×3+ (streak, no intervening write)                                         | `cramming`         |
| Bash/Shell — all other commands (write/mutate/unknown)                                      | `implementing`     |
| All other unrecognized hook events (session start/end, unknown tools, …)                    | `thinking`         |

Note: SoA gate states (`ticket_started`, `ticket_completed`, etc.) are delivered via
`gate.json` and merged by the renderer — the hook binary does not emit them.

### Known test-runner prefixes (v4)

The `testing` heuristic matches any `&&` / `;` / `||` segment beginning with:
`bun test`, `bun run test`, `bun run ci`, `bun run ci:quiet`, `bun run verify`,
`bun run verify:quiet`, `bun run format`, `bun run format:quiet`, `bun run lint`,
`bun run lint:quiet`, `bun run typecheck`, `bun run mac:test`, `npm test`,
`npm run test`, `npm run format`, `npm run lint`, `npm run typecheck`, `pnpm test`,
`pnpm run test`, `pnpm run format`, `pnpm run lint`, `pnpm run typecheck`,
`yarn test`, `yarn run test`, `yarn format`, `yarn run format`, `yarn lint`,
`yarn run lint`, `yarn typecheck`, `yarn run typecheck`, `pytest`, `cargo test`,
`go test`, `swift test`, `xcodebuild build`, `xcodebuild test`, `vitest`, `jest`,
`eslint`, `prettier`, `tsc`. `xcodebuild` segments with leading flags also match
when they contain the `build` or `test` verb later in the segment.

### Known thinking (explore) prefixes (v4)

The `thinking` heuristic matches any segment (same splitting as testing) beginning with:
`grep`, `find`, `rg`, `ls`, `cat`, `head`, `tail`, `wc`, `awk`, `jq`, `nl`, `pgrep`,
`git log`, `git diff`, `git status`, `xcodebuild -list`, or read-only `sed` (no `-i`).

## 6-Tier User Model

Phase 07 locks the 6-tier animation model from research §7:

| Tier | Configuration           | Available states (hook)             | Available states (gate)       |
| ---- | ----------------------- | ----------------------------------- | ----------------------------- |
| 1    | Codex sheet only        | idle, standby, errored, implementing, testing (row 7), thinking (row 8) | none (no rowMap entries) |
| 2    | Codex + lite sheet      | All hook states with dedicated art  | none |
| 3    | Codex + SoA gate        | Codex Tier 1 + gate falls through   | ticket_started, adversarial_review, review_clean, ticket_completed + TEMP placeholders |
| 4    | Codex + lite + SoA gate | Tier 2 + Tier 3 combined            | full gate coverage |
| 5    | Codex + lite + RPG      | Tier 2 + RPG overlays               | none |
| 6    | Full (all sheets)       | All states                          | All gate states |

Rules:
- **Lite sheet is required for RPG** (RPG overlays are lite-sheet rows).
- **Lite sheet is recommended for SoA gates** (gate art ships on the SoA sheet which requires the lite sheet loader).
- At Tier 1 (Codex only): `testing` and `implementing` share row 7 (visual compromise); `thinking` uses row 8.
- At Tier 3: gate states with no art fall through to hook animation.

## Reliability caveats

- Heuristic states (`implementing`, `testing`, `thinking`, `reading`, `cramming`)
  reflect *observed tool use*, not intent. Renderers should treat heuristic states
  as soft hints, not authoritative claims about developer intent.
- Gate states from `gate.json` are only as reliable as the SoA orchestrator writing
  them. The renderer falls back to hook animation when `gate.json` is absent,
  expired, or points to an artless state.
- `hp` and `hp_overlay` lag real progression: they reflect the last completed
  sync, not the current second's truth.
- The hook writes one state per event with no temporal smoothing. Renderers
  that want smoothing or anti-flicker should debounce on their side.
- Gate + state.json reads happen independently on each poll tick; a one-tick
  skew between the two files is possible on fast gate writes.

## Spritesheet Asset Layout

Two spritesheets drive the renderer. The renderer loads both at startup; states
are served from the sheet that owns them. If the codogotchi sheet is absent,
states it owns degrade to `idle` (same behavior as today for unrecognized states).

### Codex sheet — `~/.codex/pets/<pet>/spritesheet.webp`

LVL 1 onboarding sheet. Owned and generated by the Codex pet system. Codogotchi
reads but never writes it. Grid: **8 columns × 9 rows**, 8 frames per row.

| Row | Codex animation name | Codogotchi state (v4)  | Notes                                      |
| --- | -------------------- | ---------------------- | ------------------------------------------ |
| 0   | `idle`               | `idle`                 |                                            |
| 1   | `running-right`      | *(reserved)*           | Future float-on-top sprite, mouse drag     |
| 2   | `running-left`       | *(reserved)*           | Future float-on-top sprite, mouse drag     |
| 3   | `waving`             | `standby`              | v3 — agent awaiting user response          |
| 4   | `jumping`            | *(reserved)*           | Future float-on-top sprite, mouse hover    |
| 5   | `failed`             | `errored`              | v2 — agent response cycle did not complete |
| 6   | *(retired)*          | *(none)*               | `waiting` (v1) retired in v4               |
| 7   | `running`            | `implementing`, `testing` | Shared row — visual compromise until lite sheet ships |
| 8   | `review`             | `thinking`             | Explore/search bucket (v4, §7)             |

Gate states (`ticket_started`, `ticket_completed`, etc.) are served exclusively
from the codogotchi sheet. They are absent from the Codex sheet by design.

### Codogotchi sheet — `~/.codogotchi/pets/<pet>/spritesheet.webp`

Supplemental sheet. Owned and generated by codogotchi. Grid: **24 columns × 9 rows**,
24 frames per row, ~167 ms per frame, ~2-second loop at 6 fps. Richer and longer
than the Codex sheet (8 frames, ~1-second loop at 8 fps).

> **Note:** 24 columns at ~6 fps yields a ~4-second loop. The **floating pet**
> plays the full row animation; the **menubar** paints a single hero frame per
> state (`heroFrameIndex = 3`, clamped) because motion is imperceptible at
> status-item scale.

| Row | Codogotchi state (v4)  | Source                                        | Notes |
| --- | ---------------------- | --------------------------------------------- | ----- |
| 0   | `review_clean`, `ticket_completed` | gate.json gate              | Shared row |
| 1   | `ticket_started`       | gate.json                                     |  |
| 2   | `green_tdd`            | gate.json                                     | TEMP placeholder (target: soa-sheet) |
| 3   | `red_tdd`              | gate.json                                     | TEMP placeholder (target: soa-sheet) |
| 4   | `open_pr`              | gate.json                                     | TEMP placeholder (target: soa-sheet) |
| 5   | `adversarial_review`   | gate.json                                     |  |
| 6   | *(none)*               |                                               | Row 6 currently unused in v4 |
| 7   | *(none)*               |                                               | Row 7 currently unused (was `reviewing`) |
| 8   | `record_review`        | gate.json                                     | TEMP placeholder (target: soa-sheet) |

TEMP rows reuse existing Codex-sheet art until `codogotchi-soa-spritesheet.webp` ships.

### Manifest format — `~/.codogotchi/pets/<pet>/pet.json`

Mirrors the shape of `~/.codex/pets/<pet>/pet.json` for consistency:

```json
{
  "id": "mali",
  "displayName": "Mali",
  "description": "...",
  "spritesheetPath": "spritesheet.webp"
}
```

The renderer resolves `spritesheetPath` relative to the pet directory. Grid
dimensions (`24 × 9`) are load-time invariants checked at startup; an
incompatible grid is a hard load failure (same policy as the Codex sheet loader).
