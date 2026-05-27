# P15.01 Add soa-event-feed.ts writer + codogotchi.enabled config gate

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- New file `tools/delivery/soa-event-feed.ts` exports `appendSoaEvent(config, projectRoot, event)` and `buildSoaEventLine(name, opts?)`.
- `appendSoaEvent` writes one NDJSON line (`JSON.stringify(event) + '\n'`) to `${projectRoot}/.soa/events.ndjson`, creating the directory if absent.
- `buildSoaEventLine` returns an object with `name`, `ts: new Date().toISOString()`, and optional `plan_key`, `ticket_id`, `payload` fields.
- `orchestrator.config.json` schema in `config.ts` accepts an optional `codogotchi: { enabled: boolean }` field; absent defaults to `enabled: true`.
- `appendSoaEvent` honors the gate: when `codogotchi.enabled === false` the call is a no-op (no directory created, no file touched).
- All write failures are absorbed inside `appendSoaEvent` — no exception propagates to the caller.
- No emit-point call sites are wired in this ticket. The writer is exercised only by its own tests.

## Red

- Add a Red test in `tools/delivery/test/p15-01.test.ts` that:
  - Creates a tmp dir, calls `appendSoaEvent(config, tmpDir, buildSoaEventLine('ticket_started', { plan_key: 'phase-15', ticket_id: 'P15.01' }))` with the gate enabled, then reads `${tmpDir}/.soa/events.ndjson` and parses the trailing line as JSON. Asserts shape: `name === 'ticket_started'`, `ts` is an ISO-8601 string, `plan_key === 'phase-15'`, `ticket_id === 'P15.01'`.
  - Calls `appendSoaEvent(config, tmpDir, ...)` twice and asserts two distinct lines, each parsing independently.
  - With the gate explicitly disabled (`codogotchi: { enabled: false }`), calls `appendSoaEvent(config, tmpDir, ...)` and asserts no `.soa/` directory was created.
  - Calls `appendSoaEvent(config, nonWritableRoot, ...)` with a non-writable `projectRoot` (e.g., a path under a read-only parent) and asserts the call returns normally with no thrown error.
- Add a focused unit test for `buildSoaEventLine` asserting the returned object has the expected keys and that `ts` parses via `Date.parse` to a finite value.
- Commit message: `test(P15.01): soa event feed writer + codogotchi gate [red]`.

## Green

- Implement `tools/delivery/soa-event-feed.ts` with `appendSoaEvent` and `buildSoaEventLine`.
- Use `node:fs/promises` (`open` with `a` flag, then write + close), wrapped in a top-level try/catch that swallows all errors.
- Use `node:fs.mkdirSync(..., { recursive: true })` (or async equivalent) to ensure `.soa/` exists.
- Add the `codogotchi` field to `OrchestratorConfig` and `ResolvedOrchestratorConfig` in `config.ts` and the parser/validator. Default normalization: absent field → `{ enabled: true }`.
- Thread `ResolvedOrchestratorConfig` into `appendSoaEvent`'s signature so the gate check happens inside the writer, not at the call site.
- Export the writer from `tools/delivery/orchestrator.ts` (the public delivery surface) so emit-point tickets can import it cleanly.

## Refactor

- Verify `appendSoaEvent` is referenced only by its own tests at this point (no emit-points wired yet).
- Confirm the gate check happens before any filesystem call when `enabled: false` — assert via a no-`.soa/`-created test.
- No move/rename — `SOA_TARGET_VERSION` bump not required.

## Review Focus

- The writer never throws under any input (read-only paths, non-existent parents, gate disabled, malformed event object).
- `buildSoaEventLine` produces lines that pass codogotchi's zod `.passthrough()` schema — `name` and `ts` are required strings; everything else is optional.
- Config schema additions follow the existing pattern for optional structured fields (`reviewPolicy`, etc.).
- The `codogotchi` config field default is `enabled: true` when absent — verified by config-parser tests.
- No emit-point calls in this PR; surface is the writer module + config schema + tests only.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Cannot find module '../soa-event-feed'` — all 6 tests failed immediately on the missing module.
Why this path: `appendSoaEvent(config, projectRoot, event)` puts the gate check inside the writer, avoiding scattered `if (config.codogotchi?.enabled !== false)` guards at every call site. `node:fs/promises open(..., 'a')` is the minimal append-mode write that doesn't require reading the file first.
Alternative considered: Passing only a boolean `enabled` flag instead of full config — rejected because future fields (e.g. custom path) would require a new signature change; passing the resolved config is the same pattern as other helpers in this codebase.
