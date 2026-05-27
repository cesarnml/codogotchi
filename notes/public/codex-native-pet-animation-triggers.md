# Native Codex Pet Animation Trigger Findings

Date: 2026-05-27

This note captures reverse-engineered findings for the native Codex desktop pet
animation trigger dynamics (not codogotchi mapping). The analysis was based on
local inspection of the installed `Codex.app` bundle and pet assets.

## Scope and method

- Inspected local pet packs in `~/.codex/pets/<pet>/` (`pet.json` + `spritesheet.webp`).
- Extracted `/Applications/Codex.app/Contents/Resources/app.asar`.
- Traced overlay/avatar bundles:
  - `webview/assets/codex-avatar-*.js`
  - `webview/assets/avatar-overlay-page-*.js`
  - `webview/assets/avatar-mascot-button-*.js`
  - `webview/assets/app-server-manager-signals-*.js`

## Runtime model summary

Codex uses a layered state model:

1. **Session status** is computed (`idle | waiting | running | review | failed`)
   from local conversation and remote task signals.
2. Session status becomes a notification with priority and level.
3. Highest-priority notification drives mascot state.
4. Floating UI interaction can temporarily override mascot state
   (`jumping`, `running-left`, `running-right`).

Important: non-idle animations are played as a burst pattern (state frames
repeated, then eased back to idle), not an infinite fixed-state loop.

## Confirmed row/state mapping

From the avatar bundle state table:

- `idle` -> row `0`
- `running-right` -> row `1`
- `running-left` -> row `2`
- `waving` -> row `3`
- `jumping` -> row `4`
- `failed` -> row `5`
- `waiting` -> row `6`
- `running` -> row `7`
- `review` -> row `8`

## Trigger dynamics (plain English + technical)

### `idle` (row 0)

- English: no active work that needs your attention.
- Technical: session resolves to `idle`; no active top notification.

### `running-right` / `running-left` (rows 1/2)

- English: pet moves while you drag it horizontally.
- Technical: drag delta threshold (`>= 4` or `<= -4`) maps to transient
  `running-right` / `running-left`. This is pointer interaction, not agent
  workload state.

### `waving` (row 3)

- English: greeting when opening the floating pet.
- Technical: `first-awake` notification kind maps to mascot `waving`.

### `jumping` (row 4)

- English: hover/attention response.
- Technical: pointer hover sets transient state `jumping` in mascot button.

### `failed` (row 5)

- English: task blocked/failed/cancelled.
- Technical: failed session status maps to notification level `danger`, then
  mascot `failed`.

### `waiting` (row 6)

- English: Codex is waiting for your input/approval.
- Technical: waiting conditions include user-input requests, approvals,
  permissions, MCP elicitation, and incomplete plan implementation waiting
  paths. Mapped to warning-level notification and mascot `waiting`.

### `running` (row 7)

- English: Codex is actively working.
- Technical: running session status marks notification `isLoading`, and loading
  maps to mascot `running`.

### `review` (row 8)

- English: output is done and ready for your review.
- Technical: unread completed output status maps to success-level notification
  and mascot `review`.

## Priority and precedence

### Session-status priority (notification sorting)

Highest to lowest:

1. `waiting`
2. `failed`
3. `review`
4. `running`
5. `idle` (effectively omitted from active notifications)

### Mascot resolution precedence

1. `first-awake` -> `waving`
2. `isLoading` -> `running`
3. `warning` -> `waiting`
4. `danger` -> `failed`
5. `success` -> `review`
6. fallback -> `idle`

### Interaction overrides

- Pointer transient states (`jumping`, `running-left`, `running-right`) override
  session-derived mascot state while active.

## Timing constants observed

From the overlay bundle:

- Running notification TTL: `180 * 1e3` (3 minutes)
- Failed notification TTL: `3600 * 1e3` (1 hour)
- Waiting notification TTL: `1440 * 60 * 1e3` (24 hours)
- Review notification TTL: `10080 * 60 * 1e3` (7 days)
- First-awake greeting TTL: `8 * 1e3` (8 seconds)

## Caveats

- Findings are tied to the inspected local Codex app build and may change in
  future releases.
- The pet manifest currently does not expose custom trigger rules; event/state
  mapping and playback behavior are app-owned.
