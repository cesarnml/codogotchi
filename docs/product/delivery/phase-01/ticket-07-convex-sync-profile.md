# P1.07 Convex `syncProfile` mutation + HTTP action

Size: 2 points
Type: feat
Scope: convex

## Outcome

- `convex/mutations/syncProfile.ts` exports a mutation that accepts `{ profile_id, handle, signals: { claude, codex, github, wakatime } (each nullable), config, now }` and:
  - Looks up the existing profile by `profile_id` (creates if not found, using handle).
  - For each non-null source, calls `computeXp` from `@codogotchi/engine` and updates `xp_by_source[source]` + `last_signal_at_by_source[source]`.
  - For each null source, skips (preserves prior totals).
  - Recomputes aggregate `total_xp`, `stage` via `stageForXp`.
  - Calls `tickHealth` with `now`, current profile health, merged signals, and `config`. Persists resulting HP / mood / death fields.
  - Rolls loot via `rollLootDrop` / `rollPRLootDropWithQuality`: Claude and Codex only roll when that source's `tokens > 0`; GitHub rolls per merged PR in the payload; Wakatime rolls when the wakatime signal is non-null. Inserts each non-null drop into `loot_events`.
  - Returns the updated profile + any new loot events from this call.
- `convex/http.ts` registers an HTTP action at path `/sync` that parses the JSON body via zod (using `@codogotchi/contracts` schemas), invokes `syncProfile`, returns the updated profile + new loot events. Bad payloads return 400 with the zod error.
- No authentication on the HTTP action (Phase 01 policy).
- `convex-test` suite covers: new profile creation, repeat sync preserves null-source totals, two profiles do not bleed (UUIDs route correctly), loot event insertion, HP changes through synthetic time, bad payload rejection.

## Red

- Write `convex/mutations/syncProfile.test.ts` (or wherever `convex-test` conventions place it) with failing assertions: new profile created, null-source skip behavior, two-profile isolation, loot insertion.
- Run `bun test` (with convex-test wired into bun's test runner) and confirm failure.
- Commit: `test(P1.07): syncProfile mutation + HTTP action contract [red]`.

## Green

- Implement the mutation. Import engine functions; do not duplicate logic.
- Implement the HTTP action. Use `httpAction` + `httpRouter`.
- Wire zod parse at the HTTP boundary so the mutation can trust its inputs.

## Refactor

- Extract a helper if `for each non-null source` loop reads awkwardly.
- Only refactor what this ticket touches.

## Review Focus

- Server-canonical XP: confirm `total_xp` is recomputed from `xp_by_source`, never taken from the request. Grep request shape — should not contain `total_xp` or pre-computed numbers.
- Per-source null = skip semantics work as documented in the plan: prior `xp_by_source[source]` is preserved when payload source is null.
- Two-profile isolation test exists and passes; reviewer reads the test to confirm it really uses two different UUIDs and asserts independent state.
- HTTP action 400 returns include the zod error path so a buddy onboarding badly can self-diagnose.
- Loot events have `profile_id` set correctly and indexes serve them.
- Engine imports stay pure-side only — no `sources/*` import sneaking into Convex.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- **`convex/_generated/` hand-rolled until P1.08.** `npx convex codegen` requires a registered deployment, which is the explicit scope of P1.08 (Convex production deploy + two-profile smoke). A minimal `_generated/server.ts` re-export plus a hand-rolled `convex/api.ts` function-reference registry stand in so this ticket can ship its mutation + HTTP action + convex-test suite end-to-end without inverting the ticket order. Both stubs carry an inline comment naming P1.08 as the swap point.
- **bun test ↔ convex-test bridge.** convex-test resolves function modules via Vite's `import.meta.glob`, which bun's test runner does not implement. `convex/test/modules.ts` declares the modules registry explicitly and is passed as the second argument to `convexTest(schema, modules)`. New convex function modules must be added there until codegen lands.
- **Per-source loot RNG.** The mutation uses `Math.random` directly inside the handler. Tests pin determinism via `spyOn(Math, "random").mockReturnValue(…)` per case. A pure helper accepting an injected `RngFn` was considered but rejected for Phase 01 — the convex-test stub fully exercises the integrated rolling path and a helper split would obscure where rolling actually happens.
- **Generic loot names.** `LOOT_NAMES[tier]` returns `"<tier>_drop"` strings. Display polish (tier-specific items, sprites) is explicitly deferred to later phases; the durable artifact is the tier + source on `loot_events`.
- **Post-closeout: cumulative XP + activity gates.** Outcome above says “updates `xp_by_source`” — current code **adds** each sync’s computed slice (`+=`), matching forward-only CLI windows. Claude/Codex/Wakatime apply only when tokens/hours are **> 0**; GitHub when `prs.length > 0`. Zero-activity payloads must not zero prior totals. See [`phase-01-as-shipped-delta.md`](../../plans/phase-01-as-shipped-delta.md).
