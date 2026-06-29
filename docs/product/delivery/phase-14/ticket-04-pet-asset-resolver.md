# P14.04 Swift: PetAssetResolver

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A `PetAssetResolver` resolves a `petId` to `(CodexPet, CodogotchiPet?)`, loading assets from `~/.codogotchi/pets/<petId>/` (and the bundled Maew path for `maew`).
- Results are cached by `petId`: resolving the same id twice loads the spritesheet once; two origins assigned the same pet share one loaded `CodexPet`.
- A load failure for a non-Maew pet (missing/corrupt sheet) falls back to the Maew assets rather than throwing, so a window always has something to render.
- `evict(petId:)` (or `evictAll()`) drops cached entries so a reassignment re-resolves fresh assets.

## Red

- Add `PetAssetResolverTests`: resolving an id returns assets; resolving twice hits the cache (assert the loader closure is invoked once via an injected counting loader); a failing non-Maew load falls back to Maew; eviction forces a reload.
- Run the Swift tests and confirm failures.
- Commit with suffix `[red]`: `test(menubar): pet asset resolver cache + fallback [red]`.

## Green

- Implement `PetAssetResolver` with an injectable loader closure (`(URL) throws -> CodexPet` / `CodogotchiPet`) so tests avoid real filesystem I/O.
- Reuse `CodexPet(petDirectory:)` / `CodogotchiPet(petDirectory:)` for the real loader; resolve the directory per `petId` rather than via `PetConfig.resolvedPetName()`.

## Refactor

- Keep the resolver independent of the pool and of `AssignmentsJsonReader` — it maps id → assets only. Assignment resolution stays in P14.03/P14.05.

## Review Focus

- Cache-key correctness (`petId`, not directory or origin) so shared pets dedupe.
- Fallback-to-Maew path: confirm it never throws to the caller and is observable (logged).
- Eviction completeness — a stale cached `CodexPet` must not survive a reassignment.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
