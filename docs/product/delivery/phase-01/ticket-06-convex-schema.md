# P1.06 Convex schema — profiles + loot_events + users

Size: 2 points
Type: feat
Scope: convex

## Outcome

- `convex/schema.ts` defines three tables:
  - `users`: `{ handle: string (unique index), profile_id: string (uuid), created_at: number }`.
  - `profiles`: `{ profile_id: string (uuid, unique index), handle: string, xp_by_source: { claude, codex, github, wakatime }, total_xp, stage, hp, mood, died_at: number | null, cause: string | null, death_count, last_signal_at_by_source: {...}, config_snapshot, updated_at }`.
  - `loot_events`: `{ profile_id (indexed), tier, name, source, score_explanation, ts }`.
- Indexes: `users.handle`, `profiles.profile_id`, `loot_events.profile_id` + `loot_events.ts`.
- `convex dev --typecheck` passes locally.
- No mutations defined yet — schema only. `syncProfile` lands in P1.07.
- Schema imports types from `@codogotchi/contracts` for `mood`, `xp_by_source` keys, and other shared shapes.

## Red

- Skip Red — Convex schema files are declarative. Validation comes from Convex's own typecheck and the consuming mutation tests in P1.07. Asserting schema shape in a test would re-implement Convex's typechecker.
- (If a `convex-test` fixture for shape ends up valuable, it can land in P1.07 where it has a consumer.)

## Green

- Define tables per the Outcome shape, with `defineSchema` + `defineTable` + `index(...)`.
- Use `v.union(v.literal("..."), ...)` for `mood` matching `packages/contracts/` enum exactly (or use a shared constant if Convex supports it).
- Add `convex/_generated/` to `.gitignore` if not already there.

## Refactor

- None — first definition.

## Review Focus

- Indexes match expected query patterns from P1.07: lookup by `profile_id`, list loot events by `profile_id` sorted by `ts`.
- `xp_by_source` shape exactly matches engine `XpTotals` shape — schema field names should not drift from engine.
- `mood` literal union matches contracts enum — reviewer checks both sides.
- No fields exist that no ticket plans to write or read (avoid speculative columns).
- Health-related fields present and named to match `health.ts` outputs (`hp`, `died_at`, `cause`, `death_count`).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **`mood` enum sourced from `HP_OVERLAY_STATES`.** Contracts does not export a
  separate `mood` enum, but the four HP overlay buckets (`thriving`,
  `getting_sick`, `near_death`, `ghost`) are the only mood-shaped value the
  engine currently produces and the only one the macOS app contract needs.
  Treating `mood = hpOverlay` avoids inventing a second parallel enum.
- **Loot tier/source literals locked via `satisfies readonly LootTier[]` /
  `readonly LootSource[]`.** Hardcoding the literals lets `defineSchema` keep
  Convex's `v.literal(...)` shape, while the `satisfies` assertion fails to
  compile if the engine enums drift. This is type-time drift protection
  without runtime indirection.
- **`convex dev --typecheck` deferred to P1.07/P1.08.** That CLI requires a
  Cloud project bootstrap (`convex login` + deployment) which lands in P1.08.
  Until then, repo `bun run ci:quiet` (biome + cspell) is the gate for this
  ticket. Convex-side validation comes online when `syncProfile` mutation
  tests run in P1.07 via `convex-test`.
- **`convex/_generated/` added to `.gitignore`.** Per ticket Green step; this
  directory only exists after `convex dev` has run locally.
