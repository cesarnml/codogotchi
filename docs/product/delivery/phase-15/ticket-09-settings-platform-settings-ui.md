# P15.09 Settings > Platform Settings UI

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- The Settings > Customization section titled "Platform Display Mode" is renamed **"Platform Settings"**.
- The section presents columns **Platform, Mode, Enable Session Pets, Session Cap**.
- The **Enable Session Pets** checkbox is interactive only when the platform's Mode ∈ {Own, Minimalist}; it is disabled (greyed) for Combined/Off.
- Checking Enable Session Pets exposes a **Session Cap** dropdown with options **`2`–`10` and `Unlimited`** (no `1`), defaulting to **`3`** on first enable. One cap per platform, shared across Own and Minimalist.
- `CustomizationTabViewModel` gains `setSessionPetsEnabled(_:for:)` and `setSessionCap(_:for:)`, persisting via the existing read-merge-write so unmanaged keys are never clobbered; `0` is written for Unlimited.

## Red

- Add `CustomizationTabViewModel` tests: (1) `setSessionPetsEnabled(true, for:)` writes `session_pets_enabled[origin] = true` and merges without clobbering `platform_modes`; (2) `setSessionCap` writes the int, with Unlimited persisted as `0`; (3) enabling for the first time yields the default cap 3 at the read point; (4) toggling mode to Combined does not erase a previously stored cap (cap persists, checkbox just disables).
- Run the suite; confirm failures. Commit `test(P15.09): platform-settings session-pets VM persistence [red]`.

## Green

- Add the two VM methods (read-merge-write via `ConfigFileWriter.merge`, mirroring `setMode`/`setTTL`).
- Update `SettingsWindowController` Platform Settings card: rename title, add the Enable Session Pets checkbox column (enabled predicate on Mode) and the Session Cap dropdown (2–10 + Unlimited), wired to the VM. Default the dropdown to 3 when first enabled.

## Refactor

- Reuse the existing per-platform row layout and control-styling helpers in `SettingsWindowController`; add two columns rather than a new card.
- Keep default-3 / Unlimited-as-`0` interpretation consistent with the consumers (P15.04/P15.07) — single source of truth for the sentinel.

## Review Focus

- Checkbox interactivity predicate: live only for Own/Minimalist; confirm Combined/Off disables (not hides) and preserves any stored cap.
- Dropdown offers 2–10 + Unlimited (no 1) and defaults to 3 on first enable; Unlimited round-trips as `0`.
- Read-merge-write does not clobber `platform_modes`, `idle_dismiss_ttl_seconds`, `minimalist_badge_scale`, or `menubar_icon_monochrome`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
