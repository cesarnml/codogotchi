# P5.04 Bundled Maew + canonical pet store

Size: 3 points
Type: feat
Scope: pet-store
Red: required

## Outcome

- App bundle includes Maew: `pet.json`, `spritesheet.webp` (Codex 8×9 grid), `codogotchi-spritesheet.webp` under Resources (source from `apps/menubar/Fixtures/maew/` plus Codex sheet — add `spritesheet.webp` to Maew fixtures if only Mali has it today).
- On first launch (before onboarding sheet if ordering requires pet visible): if `~/.codogotchi/pets/maew/` is missing or incomplete, copy bundle assets into canonical store.
- `CodexPet.defaultPetDirectoryPath()` and `CodogotchiPet.defaultPetDirectoryPath()` resolve `~/.codogotchi/pets/<PetConfig.resolvedPetName()>/` only — **not** `~/.codex/pets/`.
- `MenubarApp` launches renderer with idle Maew when canonical store is seeded — no pawprint-only failure on clean machine without `~/.codex/`.
- `CODOGOTCHI_HOME` overrides pet paths consistently with config (audit/fix gaps).
- Floating pet uses same pet resolution as menu bar.

## Red

- Write failing Swift tests: seed copies both sheets; loader paths under temp `CODOGOTCHI_HOME`; launch wiring succeeds without `~/.codex/pets`.
- Commit: `test(P5.04): bundled maew seed and canonical pet paths [red]`.

## Green

- Add bundle resources + copy helper (idempotent seed).
- Update `CodexPet` / `CodogotchiPet` default paths.
- Adjust `MenubarApp` catch path so missing Codex sheet after failed seed is logged clearly.

## Refactor

- Update `CodexPet` header comments that still say `~/.codex/pets/mali/`.
- Do not implement Settings pet import (P5.07).

## Review Focus

- Seed is idempotent (second launch does not duplicate or corrupt).
- Asset size acceptable for dev `.app` builds.
- Tests do not require owner's home directory.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
