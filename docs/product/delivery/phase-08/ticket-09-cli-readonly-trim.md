# P8.09 Public CLI read-only trim

Size: 2 points
Type: refactor
Scope: cli
Red: required

## Outcome

- `codogotchi --help` lists only read/diagnostic commands plus `rpg`/`enroll`: `status`, `hooks status` are shown; `setup`, `hooks install`, `hooks uninstall` are **hidden** from help.
- The hidden commands remain **fully functional when invoked directly** — the app's install API still spawns `hooks install`/`uninstall` as subprocesses. Hiding ≠ removing.
- `rpg` / `enroll` remain visible (no in-app replacement until Phase 09).
- Hidden commands are marked internal/deprecated in help text so a curious user understands they are app-managed.

## Red

- Test `--help` output excludes `setup`, `hooks install`, `hooks uninstall`.
- Test `--help` still includes `status`, `hooks status`, `rpg`, `enroll`.
- Test the hidden commands still execute (parse + dispatch) when invoked explicitly — they are hidden, not deleted.
- Run the suite; confirm failure. Commit `[red]`.

## Green

- In the CLI router/registration (`router.ts` / `index.ts`), mark `setup`, `hooks install`, `hooks uninstall` as hidden from help while keeping their dispatch intact; add an internal/deprecated note.

## Refactor

- Centralize the "hidden but callable" flag rather than special-casing help rendering per command.

## Review Focus

- **Hidden, not removed** — the app's subprocess calls (`SettingsController`, `OnboardingController`) must keep working. Verify the app path still functions after the trim.
- That `rpg`/`enroll` are untouched (Phase 10 dependency).
- Help copy makes clear these are app-managed, not broken.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: testUsageDoesNotListSetup, testUsageDoesNotListHooksInstall (USAGE still contained those strings).
Why this path: the install API still needs the subcommands; only the public surface (help) is trimmed.
Alternative considered: delete the subcommands — rejected; would break the app's own install path.
Implementation: USAGE string rewritten to omit setup, hooks install, hooks uninstall; adds a note directing users to Settings → General. Flags section updated (removed "setup" from "Flags (setup, rpg)"). Dispatch for all hidden commands unchanged.
Deferred: `rpg`/`enroll` removal (Phase 09); standalone-CLI-package `--help` trim (follow-up).
