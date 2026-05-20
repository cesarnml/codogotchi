# P2.04 Swift MaliPet asset loader + hardcoded row-map table

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `apps/menubar/Sources/MaliPet.swift` exposes a `MaliPet` type with:
  - `init(petDirectory:)` taking a path (defaults to `~/.codex/pets/mali/`); reads `pet.json` and `spritesheet.webp`.
  - A hardcoded `[ActivityState: RowSpec]` table mapping each of the four floor states to a `(rowIndex: Int, frameCount: Int)` tuple. Mapping is determined by visual inspection of `spritesheet-grid-8x9.png` (8 columns × 9 rows). The exact row assignments are committed in the Swift source with an inline comment naming each row's source in the grid PNG.
  - `frames(for: ActivityState) -> [NSImage]`, returning the per-state animation frames sliced from the spritesheet at runtime via `CGImage.cropping(to:)` (or equivalent). Frame width = spritesheet width / 8; frame height = spritesheet height / 9.
- Loader tolerates the WebP spritesheet via `NSImage(contentsOfFile:)`; if WebP loading proves unstable in practice, document the workaround in the Rationale section and convert the PNG variant for fixtures.
- `apps/menubar/Fixtures/mali/` contains a committed copy of `pet.json` + `spritesheet.webp` so unit tests run without touching `~/.codex/`.
- Tests at `apps/menubar/Tests/MenubarTests/MaliPetTests.swift`:
  - Loading from the fixture directory succeeds and produces a `MaliPet` instance.
  - `frames(for: .implementing)` returns a non-empty `[NSImage]` whose first element has the expected pixel dimensions (rowHeight × frameWidth).
  - `frames(for: .idle)`, `.runningTests`, `.celebrating` each return a non-empty array.
  - Pet directory missing → loader throws or returns a `MaliPetLoadError` with a clear case.
- `notes/private/phase-02-swift-notes/P2.04-mali-pet-loader.md` lands in this PR explaining: `NSImage` vs. `CGImage`, `CGImage.cropping(to:)` rect coordinates (top-left vs. bottom-left origin gotcha), and the spritesheet slicing approach in TS-dev terms.

## Red

- Write `MaliPetTests` first. Run `bun run mac:test`; confirm tests fail because `MaliPet.swift` does not exist.
- Commit with suffix `[red]`: `test(P2.04): mali pet loader extracts frames per floor state [red]`.

## Green

- Inspect `spritesheet-grid-8x9.png` visually to determine which row index corresponds to each of the four floor states. Record the mapping as an inline comment in the row-map table.
- Implement `MaliPet` with `pet.json` parsing (the minimal fields: `id`, `displayName`, `spritesheetPath`) and the hardcoded row-map table.
- Implement frame slicing via `CGImage.cropping(to:)`.
- Copy a fresh `pet.json` + `spritesheet.webp` from `~/.codex/pets/mali/` into `apps/menubar/Fixtures/mali/` for test isolation.
- Make tests pass.

## Refactor

- If the row-map determination requires owner confirmation ("row 3 = implementing, yes/no?"), record the question, stop, and ask before guessing. Wrong row assignments will be visually obvious in P2.05 but ugly to chase later.
- If WebP loading via `NSImage(contentsOfFile:)` is flaky in tests, fall back to ImageIO (`CGImageSourceCreateWithURL`) or convert the fixture to PNG. Document choice in Rationale.
- Confirm the loader does not retain unnecessary references — the spritesheet image bytes can be large; sliced `NSImage`s should reference the same `CGImage` or be small copies, not full re-decodes.

## Review Focus

- Row-map mapping: is each row's correspondence to its `ActivityState` justified in the inline comment with a reference to a grid PNG cell, not a guess?
- Frame extraction: are coordinates correct for the spritesheet's coordinate system (Cocoa flipped coordinates can bite here)?
- Test isolation: the fixture copy in `apps/menubar/Fixtures/mali/` should be independent of `~/.codex/pets/mali/` — running the test suite on a machine without that directory should still pass.
- The Swift notes file: explains coordinate systems and slicing clearly enough for a TS-only reviewer to recognize when the code is suspicious.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: tests assert frame extraction returns non-empty arrays with expected dimensions before the implementation exists.
Why this path: hardcoded `[State: RowSpec]` in Swift was chosen over `pet.json` extension or sibling rows file because (a) only one pet is in scope, (b) no consumer needs the format extension yet, (c) the mapping is visible in code review, and (d) Phase 06 catalog is the right place to formalize a multi-pet row-map convention.
Alternative considered: sibling `codogotchi-rows.json` in the pet directory. Rejected because it creates a "missing rows file" failure mode and a soft format extension outside any contract doc.
Deferred: multi-pet support, malformed-pet handling, runtime pet picker. All Phase 06 (catalog).
Contract note: if WebP loading workarounds were needed, record the chosen approach (fallback library, PNG conversion, etc.) here.

Row map (owner-confirmed 2026-05-21 against `spritesheet-grid-8x9.png`):
`.idle` = row 0, `.implementing` = row 7, `.runningTests` = row 8,
`.celebrating` = row 4. Frame counts (8 / 6 / 4 / 5 respectively) are
visual estimates of leading non-magenta cells per row — wrong counts
will be visually obvious in P2.05's renderer and easy to fix in
`MaliPet.rowMap`.

ci gate extension: `bun run ci` (and `ci:quiet`) now chain `bun run
mac:test` so the orchestrator's `post-red` step sees a failing Swift
test as a failing ci run. Without that, post-red refused this ticket's
`[red]` commit (biome+cspell are TS-only and could not observe the
Swift compile failure). Future Swift tickets inherit the same gate.

WebP loading: `NSImage(contentsOfFile:)` decoded `spritesheet.webp` on
macOS 13+ without a third-party library — no workaround needed for this
ticket. Documented fallback paths (`CGImageSourceCreateWithURL`, PNG
conversion) remain in the Swift notes if a future macOS target loses
WebP support.
