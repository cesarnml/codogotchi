# Codogotchi: Event-driven + Mouse-interaction Animation Implementation

Date: 2026-05-27

This note summarizes how **Codogotchi** implements event-driven animations (agent lifecycle → `state.json` → renderer) and how it overlays **mouse-interaction** animations on the **floating pet** surface.

This is intentionally about Codogotchi’s implementation mechanics, not the native Codex pet mapping.

## 1) Event-driven pipeline (agent activity → `ActivityState`)

### 1.1 Hook classification writes `~/.codogotchi/state.json`

The Codogotchi hook binary classifies an incoming “signal” into:

- an `activity_state` (closed enum),
- a `source_event` (for transition logging / debugging),
- an HP overlay (orthogonal visual tint; renderer composes it separately).

Implementation entry points:

- `packages/cli/src/hook-binary.ts` (`classifyEvent`, `runHook`)

#### SoA gate events override heuristics (precedence + “freshness”)

If a SoA gate event is present in the append-only `.soa/events.ndjson`, it wins over tool-stream heuristics:

- `runHook` reads SoA events since the stored tail offset (`readSoaEventsSince`)
- `pickLatestMappedSoaEvent` walks events from newest to oldest and returns the latest **recognized** gate mapping
- when found, `activityState` is replaced with the mapped gate state

Code anchors:

- `pickLatestMappedSoaEvent` (latest mapped gate wins)
- `runHook` (SoA gate override block)
- `SOA_GATE_TO_STATE` + `mapSoaEventToActivityState` (name → state mapping)

SoA gate mapping (canonical):

- `ticket_started` → `hyped`
- `flow_state_entered` → `focused`
- `risky_diff_detected` → `nervous`
- `pr_review_window_opened` → `waiting`
- `ticket_completed` or `review_clean_recorded` → `celebrating`
- `stage_advanced` → `ascended`
- `subagent_invoked` → `calling_for_backup`
- `verification_failed` → `panicking`

#### Heuristic classification (Claude/Codex tool-stream patterns)

If no SoA gate override fires, `classifyEvent` applies heuristics:

- `Edit` / `Write` / `MultiEdit` tool-use → `implementing`
- `Bash` tool-use:
  - `git push …` prefix → `pushing`
  - test-runner prefixes (`pytest`, `jest`, `vitest`, etc.) → `running-tests`
  - otherwise → `idle`
- `Read` tool-use:
  - counts consecutive `Read` runs across hook invocations (`readRun`)
  - only on/after `READ_RUN_THRESHOLD` (3) → `reviewing`
- `Stop` event:
  - requesting user input → `requesting_input`
  - response failure / `max_tokens` / `is_error` → `errored`
- explicit `is_error: true` (rate limit/network failures) → `errored`

Code anchor:

- `classifyEvent` in `packages/cli/src/hook-binary.ts`

### 1.2 Renderer consumes `state.json` via polling (1 Hz)

The macOS menubar app does not listen to the hook directly; it polls the file.

Implementation entry points:

- `apps/menubar/Sources/LivePollingDriver.swift`
- `apps/menubar/Sources/StateJsonReader.swift`
- `apps/menubar/Sources/MenubarRenderer.swift`

#### Poll cadence + cache

- `LivePollingDriver` polls `state.json` every `tickInterval = 1.0` seconds
- it caches last rendered `(ActivityState, VisualMode)` to avoid no-op renderer calls at 1 Hz

Code anchors:

- `LivePollingDriver.tickInterval` default + `runTick()`
- `LivePollingDriver.emit(...)` cache logic

#### Failure policy collapses to `.idle` + `.desaturated`

When the hook is missing / state payload can’t be trusted (missing file, malformed JSON, schema mismatch/newer schema), the renderer is asked to:

- set `state: .idle`
- set `visualMode: .desaturated`

Code anchor:

- `LivePollingDriver.decide(from:)`

### 1.3 Animation playback is a continuous loop per held state (menu bar + floating base)

Playback model:

- while a particular `ActivityState` is held, the renderer advances frames in a **continuous repeating timer**
- on state transitions, the renderer resets `frameIndex` and restarts the loop at frame 0

Code anchor:

- `MenubarRenderer.update(state:visualMode:)` + `restartTimer()` + `tick()`

## 2) Mouse-interaction animations (floating pet overlay)

Codogotchi implements mouse interactions as a **transient overlay** that:

1. does **not** enter `state.json` / `ActivityState`,
2. uses Codex “reserved rows” as the visual asset source,
3. overrides sprite frames during active interaction,
4. restores the last known live/demo activity frames after interaction ends.

This keeps the agent-state contract stable and isolates mouse-driven animation churn.

### 2.1 Reserved Codex rows for interactions

The floating scene uses Codex reserved interaction rows:

- `running-right` (row 1)
- `running-left` (row 2)
- `jumping` (row 4)

Codogotchi does not treat these as `ActivityState` cases. They live in a floating-only enum:

- `apps/menubar/Sources/FloatingInteraction.swift` (`FloatingInteraction`)
- `apps/menubar/Sources/MaliPet.swift` (`interactionRowMap`, `floatingFrames(forInteraction:)`)

### 2.2 Interaction lifecycle: overlay owns frames during interaction

Core scene logic:

- `apps/menubar/Sources/FloatingPetScene.swift`

Key behavior:

- `FloatingPetScene.update(state:visualMode:)` defers switching activity-state frames when `currentInteraction != nil`
- `setInteraction(nil)` restores frames derived from the latest `currentState`
- when reserved-row frames are missing (empty frames), the interaction is dropped and activity-state frames remain visible (soft fallback, no blanking)

Code anchors:

- `FloatingPetScene.update(state:visualMode:)` (interaction owns sprite → defer state swaps)
- `FloatingPetScene.setInteraction(_:)` (nil restore + empty-frame fallback)

Additional stability details:

- It preserves frame index when switching between “running-left” and “running-right”
- It has a specific “jumping → running cycle” preservation path to avoid hitching

Code anchor:

- `FloatingPetScene.setInteraction(_:)` (`preserveRunningCycle`, `preserveJumpingToRunningCycle`)

### 2.3 Mouse policy: hit-test resize handle, then map hover/drag/resize to interaction rows

All pointer-to-interaction mapping lives in `FloatingPetPanel.swift`.

Implementation entry points:

- `apps/menubar/Sources/FloatingPetPanel.swift`

#### Hit testing (where resize affordance is)

- `FloatingInteractionPolicy.resizeAffordanceSize = 28×28`
- resize affordance rectangle is the bottom-right corner of the panel:
  - `x = bounds.maxX - width`
  - `y = bounds.minY`

Code anchors:

- `FloatingInteractionPolicy.resizeAffordanceRect(in:)`
- `FloatingInteractionPolicy.hitTest(point:in:)`

#### Hover feedback (no drag)

While not dragging:

- if pointer is inside the pet bounds → `.jumping`
- otherwise → no interaction (`nil`)

Code anchor:

- `FloatingInteractionPolicy.hoverInteraction(pointerInBounds:isDragging:)`

#### Drag translation (drag region → left/right)

When the active interaction is “drag region”:

- drag step delta `delta.width > 0` → `.runningRight`
- drag step delta `delta.width < 0` → `.runningLeft`
- if `delta.width == 0`:
  - keep the previous running direction if the previous interaction was running-left, running-right, or jumping
  - otherwise return `nil` (no overlay)

This prevents “vertical-only steps” from wiping the run direction mid-drag.

Code anchor:

- `FloatingInteractionPolicy.interaction(forStepDelta:hitTarget:previous:)`

#### Resize drag (resize affordance → jumping)

When resize affordance is the active hit target:

- the overlay interaction is always `.jumping`, regardless of horizontal delta sign

Code anchor:

- `FloatingInteractionPolicy.interaction(forStepDelta:hitTarget:previous:)` (`case .resizeAffordance: return .jumping`)

### 2.4 Pointer event wiring (how interactions are emitted)

`FloatingPetPanel` drives interactions from AppKit events:

- `mouseEntered` / `mouseExited` / `mouseMoved` update hover state
- `mouseDown` picks hit target:
  - drag region → `activeInteraction = .drag(...)`
  - resize affordance → `activeInteraction = .resize(...)` + push resize cursor
- `mouseDragged`:
  - drag mode computes step delta and emits left/right interactions
  - resize mode computes raw delta and emits `.jumping`
- `mouseUp` clears interaction (`emitInteraction(nil, reason: ...)`)

To reduce churn:

- interactions are emitted only when they change (`emitInteraction` checks `interaction != lastEmittedInteraction`)

Code anchors:

- `FloatingPetPanel.mouseDown / mouseDragged / mouseUp`
- `FloatingPetPanel.emitInteraction(_:)`
- `FloatingPetPanel.syncHoverInteraction(...)`

## 3) Compare/contrast: Codogotchi vs native Codex implementation

### 3.1 Source of truth: “notification-driven” vs “state.json polling”

**Native Codex pet**

- derives pet pose from “conversation status” + a priority-ordered notification model
- uses session runtime fields (waiting/running/review/failed) to decide mascot pose
- includes time-to-live (TTL) and a “burst” playback pattern for non-idle states

**Codogotchi**

- derives `ActivityState` from:
  - hook classification (tool stream heuristics + Stop-event semantics)
  - SoA gate events (authoritative mapping from `.soa/events.ndjson`)
- writes a compact `state.json` payload
- renderer polls `state.json` at 1 Hz and plays **continuous repeating loops** while a state is held

Practical result:

- Codogotchi tends to be **more deterministic and stable across polling boundaries**
- native Codex tends to emphasize “event burst feel” via notification TTL + burst playback

### 3.2 Mouse interactions are transient overlays in both, but Codogotchi isolates them from `state.json`

Both systems have:

- hover → `jumping` visual
- horizontal drag → left/right running visual

But:

- **Native Codex** transient states are computed inside its overlay UI and can blend directly with the notification-driven status machine.
- **Codogotchi** transient states are *fully decoupled* from `ActivityState`:
  - they never enter `state.json`
  - `FloatingPetScene` explicitly defers activity-state frame swaps while interaction is active
  - interaction end restores exactly the current `ActivityState` frames (latest snapshot)

### 3.3 Differences in “how” drag selection works

Codex native (observed) uses a horizontal delta threshold and maps magnitude to left/right.

Codogotchi uses:

- a hit-test split (drag region vs resize affordance)
- a sign-based mapping on drag step `delta.width` (`>0` vs `<0`)
- a “vertical-only step” preservation rule based on the previous interaction

This is why Codogotchi’s interaction overlay can be smoother during jittery mouse movement on the first few drag ticks.

## Key code locations (for traceability)

- Hook + classification: `packages/cli/src/hook-binary.ts`
- SoA gate override: `pickLatestMappedSoaEvent` + `SOA_GATE_TO_STATE` in `hook-binary.ts`
- Polling driver: `apps/menubar/Sources/LivePollingDriver.swift`
- `state.json` read + schema checks: `apps/menubar/Sources/StateJsonReader.swift`
- Continuous playback + sheet resolution: `apps/menubar/Sources/MenubarRenderer.swift`
- Floating overlay:
  - `apps/menubar/Sources/FloatingPetScene.swift`
  - `apps/menubar/Sources/FloatingPetPanel.swift`
  - `apps/menubar/Sources/FloatingInteraction.swift`
  - `apps/menubar/Sources/MaliPet.swift` (Codex reserved interaction row slicing)
