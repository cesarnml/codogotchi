# Codogotchi native Codex pet feature-parity roadmap

Date: 2026-05-27

Goal: close the biggest UX gap between Codogotchi’s richer “activity-state” animation model and Native Codex’s “why is the pet calling for attention?” notification model.

## 0) Current parity snapshot

Matched today

- Floating mouse interactions exist (Codex reserved rows):
  - hover -> `jumping`
  - horizontal drag -> `running-left` / `running-right`
  - resize affordance -> `jumping`
- Codogotchi’s mouse interactions are a transient overlay:
  - they do not enter `state.json` / `ActivityState`
  - `FloatingPetScene` defers activity-frame swaps while interaction is active

Not yet matched (biggest gap)

- Native Codex has a built-in notification tray with:
  - a concise “reason” for why the pet is in `waiting`/`failed`/`review`/etc.
  - TTL-based expiration so pet animations decay back to `idle`
- Codogotchi currently has only the animation state + polling truth:
  - `requesting_input` / Codex `waving` can appear “stuck” for long periods if no new turn lifecycle event arrives.
  - there is no explicit “attention reason + expiry window” concept in the UI layer.

Where Codogotchi exceeds

- Higher-signal state vocabulary (implementing, running-tests, reviewing, pushing, SoA gates, etc.).
- SoA gate-event overrides via `.soa/events.ndjson`.
- Versioned `state.json` contract + controlled schema compatibility.

## 1) The single highest-value feature: “attention reasons” + TTL decay

### User story

When the pet shows an attention-critical pose (especially `requesting_input` / Codex `waving`), the user should see:

- Why: “needs approval”, “waiting for your answer”, “review output available”, “failed task”, etc.
- Since when: timestamp (or “just now / 2m ago”).
- When it will stop: TTL until the UI falls back to `idle` even if `activity_state` is still technically “waiting” due to missing follow-up events.

### Product policy (proposed)

- Add a renderer-level rule: if a reason’s `expiresAt` is in the past, renderer shows `idle` (optionally keep tooltip/indicator).
- If a new attention reason arrives, swap immediately.
- If reasons are absent, keep current behavior (fallback to existing `activity_state`).

## 2) Implementation roadmap (phased)

### Phase A: Contract extension (thin payload, low churn)

Add a minimal “reason” surface without exploding `ActivityState`:

- Extend `state.json` (or add a sibling file) with:
  - `attention`: optional object
    - `reason_kind` (e.g. `waiting_on_user_input`, `approval_request`, `review_ready`, `verification_failed`)
    - `summary` (human string)
    - `created_at`
    - `expires_at` or `ttl_ms`
    - optionally `source_event` reference for debugging

Rationale:

- Keeps animation selection decoupled from UI explanation.
- Lets renderer implement TTL decay deterministically.

Acceptance criteria

- When hook emits a `requesting_input`-class state, the renderer can show an attention reason.
- Expired reasons force `idle` even if `activity_state` remains `requesting_input`.
- Backward compatibility: older renderers ignore unknown fields; forward-compat policy remains strict on schema bumps.

### Phase B: Renderer UI and behavior

Add a Codex-like “reason tray” UX:

- Implement a lightweight tray/popover anchored near the menubar/status item.
- Show:
  - summary line
  - one or two details (optional)
  - expiry countdown or timestamp
  - “dismiss” (local ignore until next reason change)

Renderer behavior:

- If `attention.expires_at < now`:
  - show `idle` animation (and clear the tray)
- Else:
  - show animation driven by `activity_state` (or a reduced/consistent attention-specific animation).

Acceptance criteria

- “stuck waving” problem disappears:
  - if the agent completes without starting a new lifecycle signal, the tray/pose still expires.

### Phase C: Hook semantics (make reasons truthful)

Hook should produce stable reason kinds + TTL:

- For `requesting_input`:
  - reason kind: “waiting on user input”
  - TTL heuristic:
    - default match to Codex-ish “attention window” (start with 2–8 hours; tune)
- For `errored` / `panicking`:
  - TTL shorter; expired should return to idle to avoid perpetual failure pose.
- For review/complete:
  - TTL longer (days) to align “unread output available.”

Acceptance criteria

- TTL semantics correlate with real task lifetimes in practice.
- No reason emits with missing/invalid timestamps.

## 3) Dependencies and risks

Dependencies

- `state.json` is written atomically by the hook; renderer only polls it.
- Any TTL-based decay should be renderer-driven (so it works even if hook events stop).

Risks

- Misclassified reason kinds → wrong UI explanation (mitigation: start with coarse reason kinds).
- TTL tuning may require iteration (mitigation: keep TTL constants configurable behind dev flags).
- UI surface could become chatty (mitigation: reason tray only for attention states; throttle changes).

## 4) Stretch parity (nice-to-have, low effort)

- Native Codex “first-awake greeting” equivalent:
  - show `waving` / intro pose once per pet session or on first open
  - can be implemented as a transient local renderer state (no hook changes required).

## 5) What to implement first (decision)

Implement Phase A + Phase B in the smallest slice that:

1. adds `attention` payload,
2. displays “why attention”,
3. enforces TTL expiration to stop stuck `requesting_input` / waving animations.

Then tune TTL numbers based on real usage logs.

