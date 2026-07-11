# P16.06 CustomizationStore single writer

Size: 3 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `CustomizationStore` exists in `State/` and owns read-merge-write for `customization.json` plus change publication (subscribe-to-the-store API; NotificationCenter is no longer the contract).
- Exactly one call site in the app target writes `customization.json` bytes: the store.
- `CustomizationTabViewModel` and `GeneralTabViewModel` are view-facing adapters over the store; neither performs its own read-merge-write.
- Zero `CustomizationTabViewModel()` constructions outside `Settings/` — the 4 throwaway constructions in right-click handlers call the store directly.
- `.customizationDidChangeExternally` is absent from `apps/menubar/Sources` (all 7 sites removed; subscribers use the store's publication API).
- Full suite green; existing customization tests modified **only** where they constructed a VM to reach the write path — those retarget the store (the sole sanctioned test edit of the phase).

## Red

- Write `CustomizationStoreTests` first: read-merge-write preserves unrelated keys (the no-clobber contract `GeneralTabViewModel` documents today), concurrent-ish sequential writes from two adapters don't drop fields, change publication fires on write and delivers the merged result, and reads reflect external file edits.
- Run the suite and confirm the new tests fail (type does not exist).
- Commit with suffix `[red]`: `test(P16.06): CustomizationStore read-merge-write + publication [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Implement `State/CustomizationStore.swift`; fold the read path behind it (`CustomizationJsonReader` becomes its internal or its input — pick the smaller diff and note in Rationale).
- Move the merge-write logic out of `CustomizationTabViewModel` / `GeneralTabViewModel` into the store; VMs call the store and expose view-facing state only.
- Route the current writers through the store: both VMs, `MenubarApp`, `SettingsWindowController`-descended Settings code, and the FloatingPetPanel right-click handlers (post-P16.02 files).
- Replace all `.customizationDidChangeExternally` posts/observers with the store's publication API, then delete the notification name.

## Refactor

- Delete dead merge/notification plumbing left in the VMs.
- No opportunistic changes to the `customization.json` schema, key names, or merge semantics.

## Review Focus

- Write-path grep in review: exactly one site serializes `customization.json`; paste results into the PR.
- Merge semantics byte-identical for every existing writer's flow — especially the last-writer-wins interleavings between right-click switches and open Settings tabs, which is where a pre-existing bug is most likely to surface. If one is found: stop, separate commit, review-gap ledger entry.
- Publication timing: subscribers observe the same state transitions they observed via the notification (no lost or duplicated reloads while Settings is open).
- Test edits limited to write-path retargeting — flag anything broader.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: store contract tests fail (type absent)
Why this path: one ticket removes the notification in the same PR that removes its need; store in `State/` as the disk-contract owner
Alternative considered: two tickets (store+VMs, then app-side writers) — rejected; intermediate PR keeps duct tape alive and "done" ambiguous
Deferred: any customization schema/behavior change; Own/Minimalist parity work

### Implementation notes (post-GREEN)

- **`CustomizationJsonReader` fold decision**: kept as a standalone type in
  `State/CustomizationJsonReader.swift` (input to the store) rather than
  folded inline into `CustomizationStore` — smaller diff, and
  `CustomizationJsonReaderTests.swift` keeps testing the decode/clamp/default
  logic in isolation without needing a `ConfigFileWriter`-backed fixture.
  `CustomizationStore` is its sole caller.
- **Publication API**: a closure-based subscribe/unsubscribe pair on
  `CustomizationStore` (`subscribe(_:) -> Token`, `unsubscribe(_:)`, private
  `publish()` fan-out over registered closures) — not Combine, to avoid adding
  a new dependency shape for one ticket, and not NotificationCenter, per the
  ticket's explicit constraint. `merge`/`setMode`/`setCombinedMinimalistEnabled`/
  `setMinimalistBadgeScale` all accept a `notify: Bool = true` parameter: the
  Panel Size right-click pill's drag must still write every tick (so the
  on-disk value tracks the gesture) but only publish once, on the final tick
  — matching the pre-refactor behavior where the write happened every tick but
  the `.customizationDidChangeExternally` post was deferred to `isFinal`.
  Publication is per-`CustomizationStore`-instance; production code (
  `MenubarApp`) shares one instance across the right-click handlers and the
  Settings window's `CustomizationTabViewModel`/`GeneralTabViewModel` so a
  right-click write reaches an open Settings tab.
- **Self-write suppression**: `CustomizationTabViewModel` guards its store
  subscription with an `isApplyingOwnWrite` flag so its OWN writes (which
  already update its `private(set)` properties directly from the store's
  returned snapshot) do not also re-invoke `onExternalChange` — reproducing
  the pre-refactor asymmetry where the Settings tab's own control changes
  never posted the notification, only a right-click write elsewhere did.
  Without this guard, sharing one store instance between the Settings tab and
  the right-click handlers would make every Settings-tab edit also trigger a
  (harmless but unnecessary and spec-flagged) `refreshFromDisk()` on itself.
- **`SettingsWindowController`'s DI default param**: changed from
  `customizationTabViewModel: CustomizationTabViewModel = CustomizationTabViewModel()`
  to `customizationStore: CustomizationStore = CustomizationStore()` plus an
  optional `customizationTabViewModel: CustomizationTabViewModel? = nil`
  override (same pattern applied to `generalViewModel`). This is the "thread
  the store through" case the ticket anticipated: it keeps `CustomizationTabViewModel`
  construction exclusively inside `Settings/SettingsWindowController.swift`
  (the sole non-test construction site) while letting `MenubarApp` inject its
  single shared `customizationStore` without constructing a `CustomizationTabViewModel`
  itself. No existing test injects `customizationTabViewModel`/`generalViewModel`
  directly, so this was a safe, non-breaking signature change.
- **No pre-existing bug found** in the last-writer-wins interleaving the
  Review Focus flagged: `ConfigFileWriter.merge` already re-read the file
  fresh on every call before this ticket, so two writers sharing one file
  path (whether via distinct `CustomizationStore` instances, as in the new
  `CustomizationStoreTests`, or the same shared instance, as in production)
  never dropped each other's fields before or after this refactor.
- **`bun run format`**: skipped — `biome.json`'s `files.includes` excludes
  `apps` entirely, so there is nothing under `apps/menubar/` for it to
  format, and running it repo-wide risked touching files outside this
  ticket's scope.
- **Test file changes**: none of the existing `CustomizationTabViewModelTests.swift`
  or `GeneralTabViewModelTests.swift` tests construct a view model solely to
  reach the write path (all exercise domain behavior through the VM's public
  API against isolated temp-file paths) — none needed retargeting. Only new
  file: `CustomizationStoreTests.swift`.

### Subagent review findings (post-GREEN, `[subagent-review]` commit)

- **Patched — real data-loss bug**: `CustomizationStore.setMode` built its
  proposed `platform_modes` map from `snapshot.platformModes` (this
  instance's cached copy) instead of a fresh disk read. Two distinct
  `CustomizationStore` instances pointed at the same file each calling
  `setMode` for a different origin would silently drop each other's entry —
  demonstrable via `adapterA.setMode(.minimalist, for: "claude_code")` then
  `adapterB.setMode(.combined, for: "cursor")`, where B's write erased A's
  entry. This directly violated the store's own documented cross-instance
  no-clobber contract and the ticket's Red-phase requirement
  ("concurrent-ish sequential writes from two adapters don't drop fields").
  Fixed by reading `CustomizationJsonReader.read(at: filePath).platformModes`
  fresh at the top of `setMode` instead of using the cached `snapshot`.
  Regression test added:
  `testTwoAdaptersSettingDifferentOriginsInPlatformModesDoNotDropEachOther`.
  This correction supersedes the "No pre-existing bug found" note above for
  aggregate-object fields specifically — the earlier note was accurate for
  scalar top-level keys (which `ConfigFileWriter.merge` protects directly)
  but did not hold for `platform_modes`, whose internal map was rebuilt from
  a per-instance cache rather than re-merged from disk.
- **Also patched — advisory**: `testNotifyFalseSuppressesPublicationButStillPersists`
  now also asserts `store.snapshot.idleDismissTtlSeconds` (not just the
  on-disk payload) per the subagent's advisory note that the in-memory
  update on a suppressed-notify write was previously unasserted.
- **Deferred**: the subagent also found that `CustomizationTabViewModel`'s
  `isApplyingOwnWrite` flag suppresses ALL publication (not just this
  instance's own write) for the flag's synchronous duration, so a
  hypothetical re-entrant write from a different subscriber during that
  window would also be silently swallowed. Verified unreachable in current
  production wiring: the only production subscriber
  (`CustomizationTabViewModel`'s own subscription) re-syncs via
  `onExternalChange` → `Task { @MainActor in refreshFromDisk() }`, which is
  asynchronous, not a synchronous nested write; `GeneralTabViewModel` and the
  right-click handlers never subscribe. Deferred rather than patched now —
  fixing it correctly needs source-aware publication (tagging each write
  with an origin token instead of an ambient per-instance boolean), which is
  a real design change beyond this ticket's single-writer/notification-removal
  scope and isn't exercised by any current call site. Flag for a future
  ticket if a second synchronous store subscriber is ever added.
- Advisory doc-drift notes (`CustomizationJsonReader`'s actual caller list,
  the "never dropped each other's fields" phrasing) are addressed by this
  section superseding the prior claims; no further doc edit needed beyond
  this appendix.
