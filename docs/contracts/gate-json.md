# gate.json sidecar contract

`gate.json` is a short-lived sidecar file written by the Son of Anton delivery
orchestrator (son-of-anton Phase 17) and read by the codogotchi renderer. It
signals active delivery gate states — events that have a visual representation
in the codogotchi animation system and that should override the hook-driven
`activity_state` while the gate is in effect.

## Path

```
$CODOGOTCHI_HOME/gate.json
```

Default when `CODOGOTCHI_HOME` is unset: `~/.codogotchi/gate.json`.

The renderer reads this path on its standard 1 Hz poll loop, immediately after
reading `~/.codogotchi/state.json`. The two reads are independent and
best-effort; no filesystem locking is used between them.

## Ownership

| Role     | Actor |
| -------- | ----- |
| Writer   | Son of Anton delivery orchestrator (son-of-anton Phase 17) |
| Reader   | codogotchi macOS renderer (`GateJsonReader`) |
| Not used | codogotchi hook binary — the hook is a pure platform-event classifier and never reads `gate.json` |

## Shape

```json
{
  "gate": "ticket_started",
  "since": "2026-05-29T12:00:00.000Z",
  "expires_at": "2026-05-29T12:03:00.000Z",
  "plan_key": "phase-07",
  "ticket_id": "P7.01"
}
```

| Field        | Type   | Required | Description |
| ------------ | ------ | -------- | ----------- |
| `gate`       | string | Yes      | ActivityState raw value (snake_case). Must be a v4 schema enum member. |
| `since`      | string | Yes      | ISO 8601 timestamp when the gate became active. |
| `expires_at` | string | Yes      | ISO 8601 timestamp after which the gate expires. Renderer falls through to hook animation once `now > expires_at`. |
| `plan_key`   | string | No       | Delivery plan key (e.g. `"phase-07"`). Informational; not used by the renderer. |
| `ticket_id`  | string | No       | Ticket ID (e.g. `"P7.01"`). Informational; not used by the renderer. |

Both `since` and `expires_at` use ISO 8601 with either fractional seconds
(`"2026-05-29T12:00:00.000Z"`) or whole seconds (`"2026-05-29T12:00:00Z"`).
The renderer accepts both forms via a two-pass parse. An unparseable
`expires_at` is treated as expired — the gate is ignored rather than
activating indefinitely.

## Merge precedence (renderer)

The renderer resolves the final `ActivityState` from gate + hook using this
chain (highest priority first):

**Phase 12 note (Option 2 / ambient gate):** "hook animation" in this chain refers to the
`globalAggregate`-resolved state from `state.d/` — the single winner across all concurrent
sessions. The gate overrides the aggregate, not any individual per-session slice. Per-session
gate stamping (`origin, session_id` in `gate.json`) is **Option 1** and is deferred to the
v3 per-thread phase (upstream `cesarnml/son-of-anton` work).

1. **Unexpired gate with a sprite row** — `expires_at > now` AND the gate
   name maps to a valid `ActivityState` AND that state has an entry in
   `CodogotchiPet.rowMap`. The gate state is rendered.
2. **Expired gate** — `expires_at <= now`. Fall through to hook animation (global-aggregate).
3. **Unknown/skew gate** — the `gate` string is not a valid v4 `ActivityState`
   raw value. Fall through to hook animation; no crash.
4. **Artless gate** — the gate state is a valid v4 state but has no sprite row
   (e.g. `advance`, `poll_review`). Fall through to hook animation.
5. **Absent gate.json** — file is missing. Hook animation only (global-aggregate).
6. **Malformed gate.json** — JSON is invalid or required fields are missing.
   Treated as absent; no error surfaced to the user.

The "has a sprite row" check (`CodogotchiPet.rowMap[state] != nil`) is the
single gate-renderability predicate. It covers both unknown-skew gates and
artless known gates with one rule.

## Temporary placeholder rows (Phase 07)

Phase 07 ships with temporary placeholder rows on the existing Codex spritesheet
for four gate states that do not yet have dedicated art:

| Gate state     | Placeholder row | Target sheet |
| -------------- | --------------- | ------------ |
| `green_tdd`    | row 2           | `codogotchi-soa-spritesheet.webp` |
| `red_tdd`      | row 3           | `codogotchi-soa-spritesheet.webp` |
| `open_pr`      | row 4           | `codogotchi-soa-spritesheet.webp` |
| `record_review`| row 8           | `codogotchi-soa-spritesheet.webp` |

These are visual compromises. The dedicated gate art ships with the
`codogotchi-soa-spritesheet.webp` asset in a future phase.

## Gate states with permanent rows

| Gate state          | Row | Notes |
| ------------------- | --- | ----- |
| `review_clean`      | 0   | Shared with `ticket_completed` |
| `ticket_completed`  | 0   | Shared with `review_clean` |
| `ticket_started`    | 1   |  |
| `adversarial_review`| 5   |  |

## Known gap

The following v4 SoA gate states have no sprite row and fall through to hook
animation. They will render via the hook's `activity_state` until art and
orchestrator event wiring land in a future phase:

`advance`, `poll_review`, `red_tdd`\*, `green_tdd`\*, `open_pr`\*, `record_review`\*

(\* have temporary placeholder rows per the table above; will get dedicated art)

## Cross-references

- Son of Anton Phase 17 (`docs/product/plans/phase-17-codogotchi-direct-gate-write.md`
  in the son-of-anton repo) — the producer implementation.
- `docs/contracts/animation-state-vocabulary.md` — v7 ActivityState enum, slice-directory model, and `globalAggregate` reducer.
- `apps/menubar/Sources/GateJsonReader.swift` — renderer implementation.
- `apps/menubar/Sources/StateJsonReader.swift` — `readDirectory(at:)` and `globalAggregate` collapse (Swift side).
