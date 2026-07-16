# P21.04 Disk-only SessionPruner; delete class allocator

Size: 3 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- `SessionPruner.pruneSession` no longer takes an `allocator` parameter and does not call `release` — disk-only: slice delete + label remove + retrieved-title remove.
- `FloatingPetWindowPool.pruneSession` (and any sibling call sites) no longer constructs `SessionNumberAllocator()`; number release remains solely via `PoolMemory` / `SessionNumberAllocatorState` (already performed before Pruner today).
- Class `SessionNumberAllocator` is deleted from `Sources/`. Grep under `apps/menubar` finds no remaining production references.
- Unit tests formerly against the class are migrated to `SessionNumberAllocatorState` (or deleted only if fully duplicated by existing PoolMemory allocator tests) — numbering assign/reuse/unlimited semantics remain covered.
- Behavior freeze: after Prune Session, session numbers continue to assign/reuse exactly as with today’s derive-backed allocator — no double-release, no renumber of live sessions; prune disk cleanup unchanged.

## Red

- Tests fail until `SessionPruner` API has no allocator parameter (call-site / signature assertions).
- Numbering tests fail until class-backed suites are migrated to `SessionNumberAllocatorState` and prove assign/release/reuse (including unlimited) still hold; add a prune-path regression that proves pool prune does not require a throwaway class allocator.
- Run suite; confirm red fails; commit with suffix `[red]` before green.

## Green

- Strip allocator from Pruner; update pool + tests; delete `SessionNumberAllocator.swift`; migrate `SessionNumberAllocatorTests`.
- Confirm grep is clean before deleting the class. If a live production caller appears beyond the throwaway fiction — **stop** per phase stop conditions.

## Refactor

- Only Pruner/allocator/numbering test surfaces. No flat-gate work. No Own/Minimalist extract.

## Review Focus

- Double-release must be impossible: memory release once, Pruner never releases.
- Unlimited vs bounded free-list semantics must still match pre-ticket behavior under the migrated tests.
- Do not reintroduce a facade class “for naming symmetry.”

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Surface-scan tests failed while SessionPruner still took an allocator,
the pool still constructed `SessionNumberAllocator()`, and the class file still
existed under Sources.

Why this path: Strip allocator from Pruner (disk-only); stop throwaway
construction in `FloatingPetWindowPool.pruneSession`; delete class
`SessionNumberAllocator`; migrate `SessionNumberAllocatorTests` onto
`SessionNumberAllocatorState`. Pool grep showed no live production class-
allocator caller beyond the prune throwaway fiction — proceed. Number release
remains solely in `memory.pruning` / state type.

Alternative considered: keep a facade class “for naming symmetry” — rejected
per ticket review focus.

Deferred: flat-gate fallback removal; Own/Minimalist extract.

Contract note: behavior freeze — assign/reuse/unlimited semantics unchanged
under migrated tests; no double-release (Pruner never releases).
