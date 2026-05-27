# P3.05 Pet config + Reveal pet folder menu item

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `~/.codogotchi/config.json` is read at app launch. The schema is a single key: `{ "pet": "<name>" }`. No `schema_version` field for v1 of this file (deferred per the product plan).
- File missing, JSON malformed, or `pet` key absent → fall back to the compiled-in default `"maew"`. Soft degradation, no crash, no tooltip.
- The compiled-in default lives in one constant referenced by both loaders; `"maew"` does not appear as a hardcoded literal anywhere else in `apps/menubar/Sources/`.
- Both `MaliPet` (Codex sheet) and `CodogotchiPet` (codogotchi sheet) resolve their pet directories from this single value: `~/.codex/pets/<pet>/` and `~/.codogotchi/pets/<pet>/` respectively.
- Named pet not present on disk surfaces the existing no-pet-detected failure visual (Phase 02 pattern). No crash, no busy-loop.
- A new menu item, **Reveal pet folder**, opens `~/.codex/pets/` in Finder. The codogotchi sheet's `~/.codogotchi/pets/` is not opened by this menu item — the Codex pets directory is the canonical "where pets live" surface for the user; the codogotchi sheet is a supplemental asset path.
- Test override: `$CODOGOTCHI_HOME/config.json` is read when the env var is set, mirroring Phase 02's tempdir test convention for state.json.

## Red

- Write a test that, with no config file present and no env override, the resolved pet name is `"maew"`.
- Write a test that, with `~/.codogotchi/config.json` containing `{"pet": "alice"}`, the resolved pet name is `"alice"`.
- Write a test that, with the config file containing invalid JSON, the resolved pet name falls back to `"maew"`.
- Write a test that, with the config file present but the `pet` key absent (e.g., `{}`), the resolved pet name falls back to `"maew"`.
- Write a test that `$CODOGOTCHI_HOME` overrides the resolution path (mirrors Phase 02's state.json convention).
- Write a test that both `MaliPet.defaultPetDirectoryPath()` and `CodogotchiPet.defaultPetDirectoryPath()` use the resolved name (no hardcoded `"maew"` literal in either).
- Write a test that the Reveal Pet Folder menu item invokes the expected NSWorkspace call against `~/.codex/pets/`. (Use the existing menu-test pattern from Phase 02's MenuItemsTests.)
- Run `xcodebuild test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P3.05): pet config + reveal folder [red]`.

## Green

- Add a `PetConfig.swift` (or similarly-scoped file) with a `resolvedPetName()` function returning the pet string. Default `"maew"`.
- Update `MaliPet.defaultPetDirectoryPath()` and `CodogotchiPet.defaultPetDirectoryPath()` to call `PetConfig.resolvedPetName()` instead of the hardcoded `"maew"`.
- Add the `Reveal pet folder` `NSMenuItem` to `MenubarMenu.swift` between Quit and Open log folder (or wherever fits Phase 02's menu structure). The handler opens `~/.codex/pets/` via `NSWorkspace.shared.open(...)`.
- Smallest change that makes the tests pass. No abstraction for "configurable string values from JSON" — one key, one reader, done.

## Refactor

- Confirm the resolved-name constant has a single home. Search the repo for the `"maew"` literal after Green to verify only the default-constant and the in-tree fixtures use it.
- Documentation surface: a one-line example of the config file format belongs in the README's setup section. The exact wording is P3.08's doc-drift sweep; this ticket only adds the code.

## Review Focus

- Soft degradation paths (file missing, malformed JSON, missing key) all return `"maew"` — confirm by reading the function, not just by trusting the tests.
- The hardcoded `"maew"` literal exists in exactly one place: the default constant in `PetConfig.swift`. Grep proves it.
- The Reveal pet folder menu item opens `~/.codex/pets/`, not `~/.codogotchi/pets/`. (User-facing "where are pets" lives in the Codex tree per Phase 03's design.)
- `$CODOGOTCHI_HOME` override works for the config file the same way it does for `state.json` — same pattern, no surprises.
- Pet name with a path traversal character (`"../mali"`, `"/etc/passwd"`) is either rejected at parse time or rendered harmless by `FileManager` failing to find the resulting path. Either is acceptable for Phase 03; the renderer falls back to the no-pet-detected visual.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
