# P5.11 Reveal pet folder → canonical path

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

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
