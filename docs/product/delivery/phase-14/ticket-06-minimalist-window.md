# P14.06 Swift: Minimalist window type + PromptAttentionReader summary

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A new `MinimalistWindowControlling` window type conforms to the same `FloatingPetWindowControlling` protocol the pool drives, rendering a compact badges-only strip: Platform Badge + Animation Badge + Attention Bubble + latest-prompt summary badge. No pet sprite, no RPG HUD (`applyRPGState` is a no-op).
- The pool routes origins whose mode is `.minimalist` to the minimalist factory; these windows participate in the existing spawn / idle-dismiss TTL / hide-show / last-active lifecycle identically to own-mode windows.
- A new `PromptAttentionReader` reads `~/.codogotchi/prompt-attention.json` (`by_session` store) and returns the newest entry whose key is prefixed `<origin>:` as that platform's latest-prompt summary; absent/stale/unparseable → empty (badge hidden).
- `PlatformMode` gains a `.minimalist` case; `CustomizationJsonReader` maps `"minimalist"` to it (unknown still degrades to `.own`).

## Red

- Add `MinimalistWindow` tests: applies platform/animation/attention/summary; `applyRPGState` renders no HUD.
- Add `PromptAttentionReader` tests: picks newest entry for an origin prefix; ignores other origins; absent file → empty.
- Extend pool tests: a `.minimalist` origin spawns a minimalist window and obeys TTL/hide-show/last-active like own.
- Run the Swift tests and confirm failures.
- Commit with suffix `[red]`: `test(menubar): minimalist window + prompt-attention reader [red]`.

## Green

- Add `.minimalist` to `PlatformMode` and the `CustomizationJsonReader` mapping.
- Implement `MinimalistWindowControlling` + its panel/controller, composing the existing badge/attention views without the sprite/HUD layers.
- Implement `PromptAttentionReader`; wire it into the minimalist window's summary badge update.
- Branch the pool factory: `.minimalist` → minimalist factory; `.own` → existing pet factory.

## Refactor

- Reuse the existing platform/animation badge and attention-bubble views by composition; do not fork their rendering.
- Keep minimalist geometry (compact strip) independent of the pet-window frame math.

## Review Focus

- Lifecycle parity: minimalist windows must dismiss/hide/last-active exactly like own windows (reuse the same pool code paths, not a parallel one).
- Summary attribution: confirm the `<origin>:` prefix match is correct and does not bleed across platforms.
- Guarantee no sprite and no HUD ever render in minimalist mode (the `applyRPGState` no-op and absent sprite layer).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `bun run mac:test` failed at compile with `PlatformMode` missing `.minimalist`, before the new pool/controller/reader seams existed.
Why this path: Added minimalist as an additional pool-routed `FloatingPetWindowControlling` implementation so TTL, hide/show, last-active, and activity/attention fanout stay on the existing pool lifecycle.
Alternative considered: Reusing `FloatingPetPanelController` with the sprite hidden was rejected because it would keep HUD/sprite lifecycle state alive and make the no-HUD/no-sprite guarantee weaker.
Deferred: Richer minimalist styling and SoA gate/ticket badges in minimalist mode remain out of this ticket.
Contract note: No state schema bump; `customization.json` remains schema_version 1 with unknown modes still degrading to `.own`.
