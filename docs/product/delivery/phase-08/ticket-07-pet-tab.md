# P8.07 Pet tab — enumerate/select/import + Maew default

Size: 2 points
Type: feat
Scope: settings
Red: required

## Outcome

- The Pet tab lists pets from three sources: **Codex built-in** (`~/.codex/pets/` when present), **custom** (`~/.codogotchi/pets/`), and the **bundled** Maew.
- Selecting a Codex/custom pet imports it via `PetImportHelper` (existing overwrite-with-rollback-backup) into `~/.codogotchi/pets/<id>/`, copying `pet.json` + the lite/soa spritesheets.
- **Maew is the default**: with no Codex pet imported and no prior selection, Maew is the active pet out of the box.
- The active selection persists and drives the renderer; switching pets updates the live pet.

## Red

- Test enumeration merges the three sources without duplicates and tolerates a missing `~/.codex/pets/`.
- Test default selection resolves to Maew when nothing else is selected/imported.
- Test selecting a pet persists the choice and that import delegates to `PetImportHelper` (overwrite-with-backup) — not a re-implementation.
- Run the suite; confirm failure. Commit `[red]`.

## Green

- Build the Pet tab list view-model over the existing `PetImportHelper.availableCodexPets()` + a custom/bundled scan; wire select→import→activate.
- Persist the active pet id; notify the renderer.

## Refactor

- Reuse the existing import/seed helpers (`PetImportHelper`, `PetStoreSeeder`); only add enumeration/selection glue.

## Review Focus

- Default-to-Maew when the store is empty (fresh install) — the pet must render immediately after onboarding.
- Overwrite semantics on re-import (safe backup/rollback) — confirm it delegates, not duplicates.
- No assumption that `~/.codex/pets/` exists.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: extend the existing pet section + helpers rather than rebuild import.
Alternative considered: versioned-copy import — rejected; canonical store is a copy, overwrite-with-backup is sufficient.
Deferred: BYOP full validation (Phase 12); multiple bundled pets (post-launch).
Contract note:
