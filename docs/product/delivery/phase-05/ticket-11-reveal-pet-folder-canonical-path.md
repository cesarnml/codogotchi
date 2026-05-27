# P5.11 [Reveal pet folder → canonical path]

Size: 1 point
Type: fix
Scope: menubar-menu
Red: required

## Outcome

- **Reveal pet folder** menu item opens `~/.codogotchi/pets/` (respecting `CODOGOTCHI_HOME`), not `~/.codex/pets/`.
- `MenubarMenu.defaultPetFolderURL()` and tests updated.
- Menu comment/docs strings no longer claim Codex directory is the reveal target.

## Red

- Update `MenuItemsTests` (or equivalent) to expect canonical path suffix `/.codogotchi/pets`.
- Run `bun run mac:test`; confirm test fails on current branch.
- Commit: `test(P5.11): reveal pet folder opens canonical store [red]`.

## Green

- Change URL construction and any related copy.

## Refactor

- None beyond touched menu files.

## Review Focus

- Aligns with P5.04 canonical store; small but user-visible fix.

## Rationale

Pattern mirrors `PetConfig.configURL()`: `getenv("CODOGOTCHI_HOME")` → non-empty string → use `$CODOGOTCHI_HOME/pets`; otherwise fall back to `~/.codogotchi/pets`.

Subagent review found two gaps patched before open-pr:
1. Missing `.isEmpty` guard — empty `CODOGOTCHI_HOME` produced a CWD-relative URL instead of the canonical home path.
2. The `CODOGOTCHI_HOME` env-var branch was untested; added `setenv`/`unsetenv` guard to the existing test and a new test covering the custom-home path.

Deferred: `defaultLogFolderURL()` does not respect `CODOGOTCHI_HOME` — advisory observation, follow-up ticket.
