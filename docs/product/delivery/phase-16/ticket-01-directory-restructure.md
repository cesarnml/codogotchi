# P16.01 Directory restructure (drawers)

Size: 2 points
Type: refactor
Scope: menubar
Red: skip

## Outcome

- No `.swift` file exists at `apps/menubar/Sources/` root; all 67 files live in one of six layer directories per the assignment table below.
- The diff is 100% `git mv` renames plus any `project.yml` adjustment xcodegen requires — zero code edits.
- The project builds via xcodegen and the full existing suite is green, unmodified.
- Tests remain flat in `Tests/MenubarTests/` (locked in grill — do not mirror).

## Drawer rule

**Drawer = who owns the type at runtime, not what the name suggests.** The six drawers, per the dev guide taxonomy:

- `State/` — the disk contract: readers, writers, pruners, snapshots, stores, paths.
- `Pool/` — window pool, render keys, session policy.
- `Windows/` — panel controllers, chrome panels, prompts.
- `Scene/` — SpriteKit scene, pets, effects, asset resolution.
- `Settings/` — settings window, tabs, view models.
- `App/` — entry point, menu, menubar icon rendering, polling driver, config/demo bootstrap.

## Assignment table (all 67 files)

**State/ (23):** ActivityState, AppState, AssignmentsJsonReader, CodogotchiFolders, ConfigFileWriter, CustomizationJsonReader, GateJsonReader, HookStatusClient, HooksStatusSnapshot, LegacyStateFileCleanup, PerPlatformSnapshot, PetConfig, RetrievedSessionTitleStore, RpgStateReader, SessionLabelStore, SessionNumberAllocator, SessionPruner, SessionTitleResolver, SlicePruner, StateDirectoryListing, StateJsonReader, StateJsonWriter, TransitionLog

**Pool/ (5):** FloatingPetWindowPool, LockstepPolicy, PlatformAttribution, RenderKeyResolver, SessionSelectionPolicy

**Windows/ (14):** AttentionBubblePanel, AttentionSubtitleFormatting, ConflictBubblePayload, ConflictBubbleRateLimiter, ConflictBubbleTargetSelector, FloatingInteraction, FloatingPetController, FloatingPetPanel, OnboardingController, OnboardingWindowController, PromptTimer, RPGHUDPanel, RPGHUDViewModel, SpeechBubblePanel

**Scene/ (5):** CodexPet, CodogotchiPet, FloatingPetScene, HalfHeartDecayEngine, PetAssetResolver

**Settings/ (12):** AboutViewModel, CustomizationTabViewModel, DeveloperTabViewModel, GeneralTabViewModel, PetImportHelper, PetTabViewModel, PetThumbnail, RPGTabViewModel, SessionsTabViewModel, SettingsController, SettingsTabModel, SettingsWindowController

**App/ (8):** ConfigBootstrap, DemoConfig, DemoCycleDriver, LivePollingDriver, MenubarApp, MenubarMenu, MenubarRenderer, PetStoreSeeder

Adjudicated edge calls (locked in grill): RPGHUDPanel + RPGHUDViewModel → `Windows/` (NSPanel chrome that hosts, despite compositing visually with the scene); PlatformAttribution → `Pool/` (render-key-adjacent policy); MenubarRenderer → `App/` (status-item plumbing, not SpriteKit); FloatingPetController → `Windows/` (owns one window; `Pool/` owns the set); AppState + ActivityState → `State/` (disk-contract shapes, not app lifecycle).

Judgment-call rows an implementer may challenge at PR (flag, don't silently reassign): HalfHeartDecayEngine (`Scene/` — drives displayed decay), PromptTimer (`Windows/` — feeds the badge chip), PetThumbnail (`Settings/` — Pet tab consumer), PetStoreSeeder (`App/` — bootstrap task), PetConfig (`State/` — on-disk config shape).

## Red

- `Red: skip` — pure file moves; no testable behavior is added or changed. The existing suite passing unmodified is the gate.

## Green

- Create the six directories under `apps/menubar/Sources/`.
- `git mv` each file per the assignment table.
- Regenerate the Xcode project via xcodegen; adjust `project.yml` only if the recursive `Sources` glob does not already cover subdirectories.
- Build and run the full suite.

## Refactor

- None. This ticket is the refactor; no code edits are permitted.
- The template's `SOA_TARGET_VERSION` / `run_migration_N()` clause does not apply — it governs `.son-of-anton` tooling files, not consumer app sources.

## Review Focus

- Table-vs-diff conformance: every `git mv` matches the assignment table; no file missing, none added.
- `git log --follow` / rename detection intact (moves staged as renames, not delete+add).
- Zero content changes: `git diff -M100% --stat` shows only renames.
- `project.yml` diff (if any) limited to source-path coverage.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (`Red: skip` — moves only)
Why this path: single-ticket move is compile-neutral by construction in a single Swift target
Alternative considered: per-drawer move tickets — rejected as 6× process overhead for zero-risk moves
Deferred: test-tree mirroring (locked: flat), any code edits
