# SoA event feed (`.soa/events.ndjson`)

Son of Anton (the delivery orchestrator that ships in `.son-of-anton/`) writes
one append-only NDJSON file per project at `.soa/events.ndjson`. The
codogotchi hook binary **reads** that file to obtain explicit gate signals; it
never writes there. This document is the contract codogotchi consumes —
the SoA implementation is owned by the upstream son-of-anton repo and is
out of scope here. If the file is absent, codogotchi falls back to
Claude/Codex tool-call heuristics from `animation-state-vocabulary.md`.

> Cross-reference: the SoA-side emit ticket should link back to this doc for
> traceability.

## Path resolution

The hook resolves the project root in this priority order, then reads
`${root}/.soa/events.ndjson`:

1. `$CLAUDE_PROJECT_DIR` — set by Claude Code when invoking a hook.
2. `$CODEX_PROJECT_DIR` — set by Codex when invoking a hook.
3. The current working directory.

A missing file is **not** an error. The hook silently skips and uses the
tool-call inferred state. There is intentionally no fallback log line — a
chatty hook spams Claude Code output.

## Line schema

Each line is a JSON object terminated by `\n`. Required fields:

| Field       | Type                  | Meaning                                                   |
| ----------- | --------------------- | --------------------------------------------------------- |
| `name`      | string                | Event name. Closed enum for recognized signals; see below |
| `ts`        | string (ISO-8601)     | Time the event was emitted                                |
| `plan_key`  | string (optional)     | E.g. `phase-01`. Helps consumers filter                   |
| `ticket_id` | string (optional)     | E.g. `P1.19`. Helps consumers filter                      |
| `payload`   | object (optional)     | Free-form auxiliary data; consumers must not require it   |

Unknown event names are tolerated by the parser (zod `.passthrough()`).
Malformed lines (non-JSON, schema-fail) are skipped silently. The hook never
throws because the SoA file content is untrusted.

## Recognized event names → activity states

The codogotchi mapping below mirrors the SoA-sourced rows in
`docs/contracts/animation-state-vocabulary.md`. SoA gate signals are
authoritative — they win over Claude/Codex tool-call heuristics whenever a
**fresh** event (one seen since the last hook invocation) is present.

| SoA event name             | Activity state         |
| -------------------------- | ---------------------- |
| `ticket_started`           | `hyped`                |
| `flow_state_entered`       | `focused`              |
| `risky_diff_detected`      | `nervous`              |
| `pr_review_window_opened`  | `waiting`              |
| `ticket_completed`         | `celebrating`          |
| `review_clean_recorded`    | `celebrating`          |
| `stage_advanced`           | `ascended`             |
| `subagent_invoked`         | `calling_for_backup`   |
| `verification_failed`      | `panicking`            |

Any other `name` is silently ignored — the hook treats it as no signal at all.
Adding a new SoA event therefore requires:

1. Adding the row here.
2. Adding the row in `animation-state-vocabulary.md`.
3. Adding the name to `SOA_EVENT_NAMES` in
   `packages/contracts/src/soa-events.ts`.
4. Bumping `schema_version` only if the meaning of an existing field changes.
   New rows are additive and do not bump.

## Tail semantics

The hook tracks `(inode, offset)` of the events file in a per-home sidecar
state file (alongside the hook counter sidecar). On each invocation:

- If the file is absent, no SoA events are produced.
- If the inode matches the prior sidecar value and the offset is still within
  the file size, the hook reads only `[offset, fileSize)`.
- If the inode differs (file rotated/truncated/recreated) or the offset is
  past the current size (file shrank), the hook resets the offset to 0 and
  re-reads the whole file.

Trailing partial lines (no `\n`) are not consumed; the tail offset stops at
the last complete newline. This avoids re-emitting a partial event on the
next read.

## Precedence rule

When a hook invocation observes **both** a fresh SoA event and a Claude/Codex
tool-call event in the same step:

- The **latest** fresh SoA event wins for `activity_state`.
- The Claude/Codex tool-call still drives `source_event` if and only if no
  fresh SoA event exists.

A fresh SoA event with an unrecognized `name` does not override the
tool-stream heuristic — codogotchi only respects SoA when the event maps to a
known state.

## Producer/consumer boundary

Codogotchi is a read-only consumer of `.soa/events.ndjson`. There must be no
writes to that file (or to `.soa/` more generally) from this repo. A grep for
write paths against `.soa/` should return empty:

```bash
rg "\.soa/events" -t ts -t md | rg -v "read|tail|watch"
```

If SoA's emit path changes in the future (e.g. compressed, batched), this
contract document is the single source of truth that must be updated before
codogotchi's consumer is touched.
