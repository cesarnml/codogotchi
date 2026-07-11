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
