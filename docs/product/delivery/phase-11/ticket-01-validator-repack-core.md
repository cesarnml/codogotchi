# P11.01 Pet-package validator + canonical repack (TS core)

Size: 3 points
Type: feat
Scope: pets
Red: required

## Outcome

- A pure TS module (no Convex, no network) accepts a set of candidate pet files (or a zip buffer) and returns either a validated, canonical `.codogotchi-pet.zip` buffer + metadata, or a structured rejection with specific, fixable error messages.
- Validation enforces the contract in `plugins/hatch-codogotchi/references/codogotchi-pet-contract.md`: **Codex `spritesheet.webp` AND `codogotchi-lite-basic-spritesheet.webp` are required**; lite-enhanced and soa are optional; each present sheet matches its tier's grid (8×N) and 192×208 cell dimensions; `pet.json` parses and has the required keys; per-file and total size caps are enforced.
- Output is **allowlist-only**: the canonical zip contains exactly `pet.json` plus whichever of the four known sheet filenames were present and valid — nothing else. Any non-allowlisted or path-traversal (`../`) entry is dropped/rejected, never written.
- Metadata returned includes the tiers present and per-file byte sizes (for the `pets` row and the detail-page readout).
- Uses pure-JS libraries only (`jszip`, `image-size`); no native dependencies (no `sharp`).

## Red

- Write fixture-based tests against known-good and known-bad pet packages (small synthetic atlases at the correct/incorrect dimensions):
  - good pet (Codex + Lite-Basic) → validates, canonical zip contains exactly the allowlisted files.
  - missing `codogotchi-lite-basic-spritesheet.webp` → rejected with a "Lite-Basic required" error.
  - missing Codex `spritesheet.webp` → rejected.
  - wrong cell/grid dimensions on a sheet → rejected naming the offending tier.
  - a zip entry named `../escape.webp` (zip-slip) → rejected/stripped, never extracted.
  - a non-allowlisted extra file (e.g. `notes.txt`) → stripped from the canonical output.
  - oversized file / total → rejected on the size cap.
- Run the suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P11.01): pet-package validator contract + repack [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Implement the smallest validator + repacker that makes the fixtures pass: parse the input with `jszip`, read each sheet's dimensions with `image-size`, check against tier constants, validate `pet.json`, enforce caps, then rebuild a fresh zip from only the allowlisted, validated entries.
- Centralize the contract constants (filenames, cell size, per-tier row counts, caps) in one module so the server and tests share a single source.

## Refactor

- Extract the contract constants into a shared module importable by the Convex action (P11.03) and the CLI re-validation (P11.05); do not duplicate the numbers.
- Only refactor what this ticket touches.

## Review Focus

- The allowlist + traversal guard is the security crux — verify a malicious zip cannot cause any write outside the canonical set, and that the canonical output is rebuilt (not the input passed through).
- Confirm `image-size` reads WebP dimensions correctly for the actual atlas format; if it cannot, flag before reaching for a native codec.
- Whether the contract constants here will stay in sync with `validate_atlas.py` — note the drift risk and that fixtures are the guard.
- Deferred: thumbnail generation (client-side, P11.07) and any pixel-level/content inspection.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [any deviation from the ticket metadata contract]
