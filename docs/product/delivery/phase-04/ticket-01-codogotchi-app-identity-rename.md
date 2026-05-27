# P4.01 Codogotchi app identity rename

Size: 2 points
Type: chore
Scope: macos
Red: required

## Outcome

- The Xcode project, scheme, product name, bundle display name, and app-facing menu copy use `Codogotchi` instead of `Menubar`.
- Root `package.json` `mac:build` and `mac:test` scripts target the renamed project/scheme.
- Swift tests import the renamed app module and pass through `bun run mac:test`.
- Menu copy no longer says "Quit Menubar"; it says "Quit Codogotchi".
- The app remains an LSUIElement menu bar agent with no Dock icon and the existing menu bar renderer behavior unchanged.

## Red

- Write or update a test that asserts the quit menu title is `Quit Codogotchi`.
- Update the Swift test module import expectation to the renamed app module so tests fail before the project/scheme rename is complete.
- Run `bun run mac:test` and confirm the renamed expectation fails.
- Commit with suffix `[red]`: `test(P4.01): expect codogotchi app identity [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Rename `apps/menubar/Menubar.xcodeproj` to the Codogotchi project name.
- Update `apps/menubar/project.yml`, generated Xcode project metadata, target/scheme/product names, `Info.plist`, and Swift module references to `Codogotchi`.
- Update root `package.json` scripts to call the renamed project/scheme.
- Update user-facing menu constants and tests from Menubar to Codogotchi.
- Preserve existing app behavior: menu bar item, live polling, demo mode, transition log, pet config, and sleep/wake handling.

## Refactor

- Keep filesystem path `apps/menubar/` unless the rename toolchain proves a directory move is low-risk. The product identity matters more than moving the source folder in this ticket.
- Regenerate the Xcode project from `project.yml` rather than hand-editing generated project entries when practical.
- Do not introduce floating-pet files in this ticket.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Xcode project/scheme/script rename is complete and CI-addressable.
- User-facing copy is no longer stale.
- No behavior changes are hidden in the rename diff.
- Generated Xcode project changes match `project.yml`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:

Green implementation:
Why this path: Renamed the Xcode project, scheme, target, product, bundle display name, root macOS scripts, and menu copy to `Codogotchi` while keeping the source directory and Swift type names stable.
Alternative considered: Moving `apps/menubar/` and renaming internal `Menubar*` source types in the same ticket, but that would widen the diff beyond product identity and make generated project churn harder to review.
Deferred: Internal class/file names that describe menu-bar renderer mechanics remain as-is until a later cleanup needs them.
Contract note: The bundle identifier moved from `com.codogotchi.menubar` to `com.codogotchi.app` so the built app identity no longer carries the old product name.
