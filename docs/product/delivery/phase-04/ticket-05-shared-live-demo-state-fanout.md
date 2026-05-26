# P4.05 Shared live/demo state fanout

Size: 2 points
Type: feat
Scope: state-fanout
Red: required

## Outcome

- Live polling applies each activity-state update to both the menu bar renderer and the floating SpriteKit scene.
- Demo mode applies each fixture state to both surfaces.
- The two surfaces cannot diverge under normal update flow because they share the same fanout point.
- Failure visuals from live polling continue to affect the menu bar renderer and are represented on the floating scene consistently enough to avoid a misleading healthy desktop pet.
- Transition logging remains based on observed agent state and is not duplicated by the floating surface.

## Red

- Write tests for a state fanout helper that calls both menu and floating apply closures with the same state/mode.
- Write tests that demo mode uses the same fanout path.
- Write tests that live failure mode propagates to both surfaces.
- Run `bun run mac:test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P4.05): fan out state updates to both pet surfaces [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Extract or add a small fanout seam in `CodogotchiApp` / launch wiring.
- Route live polling success and failure outcomes to both renderers.
- Route demo cycle updates to both renderers.
- Preserve transition-log writes exactly once per observed state change.
- Ensure hidden floating panel state does not cause crashes when state updates arrive.

## Refactor

- Keep `LivePollingDriver` focused on reading and deciding; avoid making it know about concrete renderers.
- Avoid duplicating live/demo branching logic.
- Do not add new animation states in this ticket.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- One state stream drives both surfaces.
- Hidden or absent floating panel does not break live polling.
- Transition log remains semantically unchanged.
- Demo mode remains sandboxed and does not touch real `state.json`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Added a narrow `PetStateFanout` seam in the app wiring so live polling and demo mode both call the same two-target apply path. The floating panel now accepts state updates even before its scene exists, caching the latest state/mode until the panel is shown.
Alternative considered:
Let `LivePollingDriver` and `DemoCycleDriver` know about both renderers directly. Rejected because it would duplicate fanout rules in two drivers and couple polling/demo mechanics to concrete UI surfaces.
Deferred:
No scene-level assertions yet for "hidden panel later shows most recent state"; this ticket keeps the contract at the controller/panel seam and shared app fanout path.
Contract note:
`apps/menubar/project.yml` remains the Xcode source of truth; adding the new Swift source required regenerating `apps/menubar/Codogotchi.xcodeproj` with `xcodegen generate` so `mac:test` sees the file.
