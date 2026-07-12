# P17.01 Add codogotchi-gate.ts gate.json writer + CODOGOTCHI_HOME resolution

Size: 2 points
Type: feat
Scope: codogotchi-gate
Red: required

## Outcome

- A new `tools/delivery/codogotchi-gate.ts` module exposes a writer that overwrites `$CODOGOTCHI_HOME/gate.json` with `{ gate, since, expires_at, plan_key, ticket_id }`.
- Path resolves as `process.env.CODOGOTCHI_HOME ?? join(homedir(), '.codogotchi')`; the writer creates the directory if absent.
- `expires_at` is `since + 3 minutes` (flat TTL constant defined in the module).
- The write is gated on `config.codogotchi?.enabled !== false` (absent = enabled); when disabled, no file and no `~/.codogotchi/` directory are created.
- The write is best-effort: any filesystem error is swallowed so a caller never throws.
- No existing emit site is rewired in this ticket; `soa-event-feed.ts` and `events.ndjson` emission remain in place.

## Red

- Add `tools/delivery/test/p17-01.test.ts` with filesystem-level tests against a tmp `CODOGOTCHI_HOME`:
  - writing a gate produces `gate.json` parsing to the full `{ gate, since, expires_at, plan_key, ticket_id }` shape;
  - `expires_at` equals `since + 180_000 ms`;
  - `codogotchi.enabled: false` writes nothing and creates no directory;
  - an unwritable target (e.g., `CODOGOTCHI_HOME` pointing at a path whose parent is a file) does not throw.
- Run the suite and confirm the new tests fail (module does not yet exist).
- Commit with suffix `[red]`: `test(codogotchi-gate): gate.json writer + home resolution + enabled gate [red]`.
- Do not write any implementation until this commit exists on the branch.

## Green

- Implement `codogotchi-gate.ts`: a `resolveCodogotchiHome()` helper and a `writeGateEvent(config, { gate, planKey, ticketId })` (or equivalent signature) that builds the object, stamps `since`/`expires_at`, and overwrites `gate.json`.
- Mirror the best-effort `try/catch` and config-gate pattern from the retired `soa-event-feed.ts` (`appendSoaEvent`) so behavior is consistent with the prior writer's failure semantics.
- Make the smallest change that passes the tests — no call-site rewiring.

## Refactor

- Extract the 3-minute TTL as a named constant; keep the public surface minimal (one writer + the home resolver).
- Only touch the new module and its test — no opportunistic cleanup of the old writer (that is P17.04).

## Review Focus

- Path resolution matches the codogotchi hook's `getCodogotchiHome` convention (`CODOGOTCHI_HOME` env, `~/.codogotchi` default) — the renderer reads the same path.
- Single-object overwrite semantics (not append): the file holds exactly one current gate object.
- Best-effort guarantee: confirm no code path can let a write error escape to a delivery command.
- `gate` field type accepts the codogotchi schema-v4 ActivityState string values (contract-only at this layer; no enum import from codogotchi).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Cannot find module '../codogotchi-gate'` — all 4 tests failed at module resolution before any implementation existed.
Why this path: `writeFileSync` (sync) inside an async wrapper mirrors the Phase 15 `appendSoaEvent` best-effort pattern; the async surface is needed for callers that await the result. No queue or batching needed — gate writes are last-write-wins overwrites.
Alternative considered: Async `writeFile` — rejected because the sync path is simpler and the function is already best-effort; there is no benefit to buffering the write.
Deferred: Call-site wiring — no delivery commands call this module yet; that is P17.02–P17.04. No enum import from codogotchi; `gate` is an untyped string at this layer.
Contract note: No deviation from the ticket metadata contract.
