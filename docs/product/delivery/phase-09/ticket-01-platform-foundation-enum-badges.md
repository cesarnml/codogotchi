# P9.01 Platform foundation: origin enum + logo badges

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `sourceEventOriginSchema` in `packages/contracts/src/state-json.ts` accepts `vscode` and `antigravity` (alongside `claude_code`, `codex`, `cursor`, `soa`, `sync`, `manual`).
- `PlatformAttribution` (`apps/menubar/Sources/PlatformAttribution.swift`) resolves `origin: "vscode"` → `.vscode` and `origin: "antigravity"` → `.antigravity`, each with a `displayName` ("VS Code", "Antigravity") and an asset-catalog imageset name.
- Two new imagesets exist — `Assets.xcassets/PlatformVSCode.imageset/` and `PlatformAntigravity.imageset/` — each containing the supplied single-path `currentColor` SVG plus a `Contents.json` matching the existing `PlatformCursor.imageset` shape.
- A `state.json` whose `source_event.origin` is `vscode` or `antigravity` renders the correct platform logo in the animation badge and the attention bubble; `soa`/`sync`/`manual`/unknown still resolve to no chip.
- No adapter or installer logic changes in this ticket.

## Red

- Contracts (TS, `packages/contracts`): add a failing test asserting `sourceEventOriginSchema.safeParse("vscode")` and `"antigravity"` succeed (currently they reject).
- Menubar (Swift, `apps/menubar/Tests/MenubarTests/PlatformAttributionTests.swift`): add failing cases asserting `PlatformAttribution(origin: "vscode")?.assetName == "PlatformVSCode"`, `PlatformAttribution(origin: "antigravity")?.assetName == "PlatformAntigravity"`, and the two `displayName` values — plus that `"soa"`/`nil` still resolve to `nil`.
- Run the suites and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P9.01): vscode/antigravity origin enum + badge attribution [red]`.
- Do not write any implementation until this commit exists on the branch.

## Green

- Add `"vscode"` and `"antigravity"` to the `z.enum([...])` in `sourceEventOriginSchema`.
- Add `case vscode = "PlatformVSCode"` and `case antigravity = "PlatformAntigravity"` to `PlatformAttribution`, extend `init?(origin:)` with the two arms, and extend `displayName`.
- Create the two imagesets: move `~/Downloads/githubcopilot.svg` → `Assets.xcassets/PlatformVSCode.imageset/githubcopilot.svg` and `~/Downloads/antigravity.svg` → `Assets.xcassets/PlatformAntigravity.imageset/antigravity.svg`; copy a `Contents.json` from `PlatformCursor.imageset` and update the filename field.

## Refactor

- Keep the `PlatformAttribution` doc-comment accurate: it currently says "only the three coding platforms" — update the count to five.
- Only touch what this ticket changes — no opportunistic cleanup of unrelated badge rendering.

## Review Focus

- The canonical origin is `vscode`; confirm nothing in this ticket emits or maps `copilot` (alias handling is documentation-only, deferred to T04 and the adapter in T02).
- imageset `Contents.json` must match the existing template-rendering setup (single universal scale, template/monochrome rendering) so the new logos tint with the badge text like the existing three.
- Verify the SVGs are `currentColor`/single-path so they render as template glyphs; if Xcode needs `template-rendering-intent` set, mirror whatever `PlatformCursor.imageset/Contents.json` does.
- Confirm `soa`/`sync`/`manual`/unknown/absent origins still resolve to no chip (no regression to the existing nil path).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `testVSCodeOriginResolvesToVSCodePlatform` (Swift) and `sourceEventOriginSchema.safeParse("vscode").success` (TS) failed first. Both failed because neither enum had the new values.

Why this path: Adding two string literals to a `z.enum([...])` and two `case` arms to a Swift enum is the minimal correct implementation. The `assetName`/`displayName` properties extend automatically via the exhaustive switch pattern already in place.

Alternative considered: Adding a `"copilot"` alias at the contract level was considered but deferred per the grill-me decision — the canonical origin is `vscode`; alias handling is adapter-level work, not contract-level.

Deferred: `copilot` alias mapping (deferred to T02 adapter), `source_origin` usage in the hooks installer (T02/T03), and attention-bubble rendering path (already wired via `PlatformAttribution`; no change needed here).

Contract note: SVG asset filename is `githubcopilot.svg` inside `PlatformVSCode.imageset` — intentional. The imageset represents the VS Code origin driven by Copilot events, and the Copilot glyph is the correct product association. No semantic mapping of `copilot` anywhere.
