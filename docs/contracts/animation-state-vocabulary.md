# Animation State Vocabulary (v2)

The contract for the data the codogotchi hook binary writes to
`~/.codogotchi/state.json` on every relevant Claude Code / Codex lifecycle event,
and which any future renderer (macOS app, web preview, CLI ascii) consumes.

This doc defines the **closed enums** of activity states and HP overlay states,
the v2 `state.json` schema (with `schema_version`), and the mapping table from
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

Phase 03 (P3.01) is the formal v2 bump per the clause above: it appends
`requesting_input` and `errored` to the activity-state enum and raises
`STATE_JSON_SCHEMA_VERSION` from 1 to 2.

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

- Polling target file absent (the `~/.codogotchi/state.json` path does not
  exist on disk — almost certainly because the hook binary is not installed
  or has never run):
  - `codogotchi-hook not detected`
- Missing or non-integer `schema_version`, **or** malformed JSON that cannot
  be parsed as an object (both fold to the same user-facing copy — the
  distinction is not actionable for non-developer users):
  - `state.json schema_version is missing — codogotchi-hook may be too old.`
- Newer-than-expected `schema_version` (with `{got}` = observed value,
  `{expected}` = renderer's `EXPECTED_VERSION`):
  - `state.json schema_version is v{got}; this app supports v{expected}. Update the menu bar app.`

## Activity States (closed enum)

States marked **v2** are planned additions that require a `schema_version` bump to `2` before the hook binary emits them. All v1 states remain unchanged.

| State                 | Ver | Meaning                                                                                  | Source signal class                                                              | Reliability |
| --------------------- | --- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------- |
| `idle`                | v1  | No active session or no recent tool activity.                                            | Absence of recent lifecycle events. Baseline.                                    | reliable    |
| `implementing`        | v1  | Pet is writing code — Edit/Write tool usage in a coding session.                         | Claude Code / Codex tool-use events on `Edit`, `Write`, or `MultiEdit` tools.    | heuristic   |
| `running-tests`       | v1  | Pet is running test commands.                                                            | Tool-use events on `Bash` whose command matches a test runner.                   | heuristic   |
| `reviewing`           | v1  | Pet is reading code — sequential Read tool usage without edits.                          | Run of 3+ Read tool-use events with no intervening Edit/Write.                   | heuristic   |
| `pushing`             | v1  | Pet is publishing — `git push` observed.                                                 | Tool-use Bash event whose command begins with `git push`.                        | heuristic   |
| `hyped`               | v1  | Pet is energized — explicit SoA "ticket started" gate signal.                            | SoA `ticket_started` event from `.soa/events.ndjson`.                            | reliable    |
| `focused`             | v1  | Pet is deep in flow — explicit SoA "long uninterrupted session" gate signal.             | SoA `flow_state_entered` event.                                                  | reliable    |
| `nervous`             | v1  | Pet senses risk — explicit SoA "risky diff" gate signal.                                 | SoA `risky_diff_detected` event.                                                 | reliable    |
| `waiting`             | v1  | Pet is waiting on external review — explicit SoA "PR review pending" gate signal.        | SoA `pr_review_window_opened` event.                                             | reliable    |
| `celebrating`         | v1  | Pet is celebrating — explicit SoA "PR clean / ticket done" gate signal.                  | SoA `ticket_completed` or `review_clean_recorded` event.                         | reliable    |
| `ascended`            | v1  | Pet stage-advanced — explicit SoA "level up" gate signal.                                | SoA `stage_advanced` event.                                                      | reliable    |
| `calling_for_backup`  | v1  | Pet asked for help — explicit SoA "subagent invoked" gate signal.                        | SoA `subagent_invoked` event.                                                    | reliable    |
| `panicking`           | v1  | Pet is in trouble — explicit SoA "CI red / verification failed" gate signal.             | SoA `verification_failed` event.                                                 | reliable    |
| `requesting_input`    | v2  | Pet is waiting for the developer — agent paused awaiting user response.                  | Claude Code / Codex `Stop` event where the agent is requesting user input.       | reliable    |
| `errored`             | v2  | Pet is distressed — agent response cycle did not complete.                               | Agent response failure: rate limit, network error, or incomplete round-trip.     | reliable    |

`reliable` states come from explicit SoA gate events written as NDJSON to
`.soa/events.ndjson` (see `docs/contracts/soa-event-feed.md` — landing in P1.19).
`heuristic` states are inferred from raw Claude Code / Codex tool-use stream
patterns; they are best-effort and may misclassify edge cases.

The mapping from raw signal to state is single-writer: the hook binary
classifies, writes one state per event, and never blends. When SoA gate events
and tool-stream heuristics conflict, **SoA gate events win** (they are
explicit). The renderer reads the last written state; the hook does not
maintain a history.

## HP Overlay States (closed enum)

The HP overlay is orthogonal to activity state. A pet can be `implementing`
*and* `near_death` at the same time — the renderer composes the two. Buckets:

| Overlay        | HP range          | Meaning                                          |
| -------------- | ----------------- | ------------------------------------------------ |
| `thriving`     | `HP > 75`         | Healthy. No visual distress.                     |
| `getting_sick` | `25 < HP ≤ 75`    | Mild distress. Soft visual cue (color, droop).   |
| `near_death`   | `0 < HP ≤ 25`     | Heavy distress. Strong visual cue (sweat, gasp). |
| `ghost`        | `HP ≤ 0`          | Dead. Renderer shows ghost form until revived.   |

HP is server-canonical and computed in Convex's `syncProfile` mutation. The
hook binary itself does not compute HP; it writes the activity state plus the
last-seen HP overlay it received from the most recent sync. HP bucket
boundaries are confirmed by the engine implementation in **P1.04** — if P1.04
discovers a more honest curve (e.g. half-life decay around 50), it updates this
table and bumps `schema_version`.

## `state.json` v2 schema

The hook binary writes the entire object atomically (write-to-tmp + rename) on
every relevant lifecycle event. Schema:

```json
{
  "schema_version": 2,
  "activity_state": "requesting_input",
  "hp_overlay": "thriving",
  "hp": 87,
  "updated_at": "2026-05-24T21:55:00.000Z",
  "source_event": {
    "origin": "claude_code",
    "kind": "session_end",
    "name": "Stop"
  }
}
```

The shape is identical to v1; v2 only widens the `activity_state` enum to
include `requesting_input` and `errored`. Per the forward-compat policy, v1
payloads continue to parse against the v2 schema (`got=1 ≤ expected=2`).

### Field meanings

- `schema_version` — integer, starts at `1`. Future revisions bump this rather
  than silently mutating shape. Renderers branch on this and refuse unknown
  versions instead of guessing.
- `activity_state` — one of the closed activity-state enum values.
- `hp_overlay` — one of the closed HP-overlay enum values. Always derived from
  the most recently observed `hp` value; the hook does not compute it on the
  fly, it carries forward the bucket the last sync produced.
- `hp` — integer `[-100, 100]`. Below zero is permitted to model "ghost depth"
  and revival cost; the renderer treats anything ≤ 0 as `ghost`.
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

- macOS / Linux: `~/.codogotchi/state.json`
- Test override: `$CODOGOTCHI_HOME/state.json` when the env var is set
  (used by the tempdir test convention)

The hook binary creates the parent directory on first write. Read paths must
tolerate missing-file gracefully (treat as `idle` baseline).

## Mapping Table (raw signal → activity state)

This is the canonical mapping consumed by the hook binary. When two rules
could apply, the earlier row wins.

| Source signal                                                                  | activity_state         |
| ------------------------------------------------------------------------------ | ---------------------- |
| SoA event `verification_failed`                                                | `panicking`            |
| SoA event `subagent_invoked`                                                   | `calling_for_backup`   |
| SoA event `stage_advanced`                                                     | `ascended`             |
| SoA event `ticket_completed` or `review_clean_recorded`                        | `celebrating`          |
| SoA event `pr_review_window_opened`                                            | `waiting`              |
| SoA event `risky_diff_detected`                                                | `nervous`              |
| SoA event `flow_state_entered`                                                 | `focused`              |
| SoA event `ticket_started`                                                     | `hyped`                |
| Bash tool-use whose command begins with `git push`                             | `pushing`              |
| Bash tool-use whose command matches a known test runner                        | `running-tests`        |
| Edit / Write / MultiEdit tool-use                                              | `implementing`         |
| 3+ consecutive Read tool-uses with no intervening Edit/Write                   | `reviewing`            |
| Agent `Stop` event where the agent is requesting user input (v2)               | `requesting_input`     |
| Agent response failure — rate limit, network error, incomplete round-trip (v2) | `errored`              |
| Session start with no other recent activity                                    | `idle`                 |
| Session end or no events in the last 5 minutes                                 | `idle`                 |

### Known test-runner prefixes

The `running-tests` heuristic matches Bash commands beginning with any of:
`bun test`, `bun run test`, `npm test`, `npm run test`, `pnpm test`, `pnpm run test`,
`yarn test`, `yarn run test`, `pytest`, `cargo test`, `go test`, `vitest`, `jest`.
Anything outside this list stays at the prior activity state.

## Reliability caveats

- Heuristic states (`implementing`, `running-tests`, `reviewing`, `pushing`)
  reflect *observed tool use*, not intent. A pet that "reviews" three Reads in
  a row may actually be navigating to a known location. Renderers should treat
  heuristic states as soft hints, not authoritative claims about developer
  intent.
- SoA gate states are only as reliable as SoA itself writing the corresponding
  events. The hook silently falls back to heuristic states when
  `.soa/events.ndjson` is absent.
- `hp` and `hp_overlay` lag real progression: they reflect the last completed
  sync, not the current second's truth. A 30-minute streak of intense
  `implementing` does not move `hp` until the next `codogotchi sync` runs.
- The hook writes one state per event with no temporal smoothing. Renderers
  that want smoothing or anti-flicker should debounce on their side.

## Spritesheet Asset Layout

Two spritesheets drive the renderer. The renderer loads both at startup; states
are served from the sheet that owns them. If the codogotchi sheet is absent,
states it owns degrade to `idle` (same behavior as today for unrecognized states).

### Codex sheet — `~/.codex/pets/<pet>/spritesheet.webp`

LVL 1 onboarding sheet. Owned and generated by the Codex pet system. Codogotchi
reads but never writes it. Grid: **8 columns × 9 rows**, 8 frames per row.

| Row | Codex animation name | Codogotchi state       | Notes                                      |
| --- | -------------------- | ---------------------- | ------------------------------------------ |
| 0   | `idle`               | `idle`                 |                                            |
| 1   | `running-right`      | *(reserved)*           | Future float-on-top sprite, mouse drag     |
| 2   | `running-left`       | *(reserved)*           | Future float-on-top sprite, mouse drag     |
| 3   | `waving`             | `requesting_input`     | v2 — agent awaiting user response          |
| 4   | `jumping`            | *(reserved)*           | Future float-on-top sprite, mouse hover    |
| 5   | `failed`             | `errored`              | v2 — agent response cycle did not complete |
| 6   | `waiting`            | `waiting`              |                                            |
| 7   | `running`            | `implementing`         |                                            |
| 8   | `review`             | `running-tests`        |                                            |

`celebrating` is intentionally absent from the Codex sheet — the `jumping` row (4)
does not semantically match. `celebrating` is served exclusively from the
codogotchi sheet below.

### Codogotchi sheet — `~/.codogotchi/pets/<pet>/spritesheet.webp`

Supplemental sheet. Owned and generated by codogotchi. Grid: **24 columns × 9 rows**,
24 frames per row, ~167 ms per frame, ~2-second loop at 6 fps. Richer and longer
than the Codex sheet (8 frames, ~1-second loop at 8 fps).

> **Note:** 24 columns at ~6 fps yields a 2-second loop — optimized for expressiveness
> at menubar scale. The float-on-top desktop sprite (future phase) will use a
> higher-resolution version of this same sheet.

| Row | Codogotchi state      | Trigger                                          |
| --- | --------------------- | ------------------------------------------------ |
| 0   | `celebrating`         | SoA `ticket_completed` / `review_clean_recorded` |
| 1   | `hyped`               | SoA `ticket_started`                             |
| 2   | `focused`             | SoA `flow_state_entered`                         |
| 3   | `nervous`             | SoA `risky_diff_detected`                        |
| 4   | `ascended`            | SoA `stage_advanced`                             |
| 5   | `calling_for_backup`  | SoA `subagent_invoked`                           |
| 6   | `panicking`           | SoA `verification_failed`                        |
| 7   | `reviewing`           | 3+ consecutive Reads with no intervening Edit    |
| 8   | `pushing`             | `git push` Bash command                          |

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
