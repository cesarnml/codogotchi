# P21.04 Per-platform model and effort selection with ledger fidelity

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- `orchestrator.config.json` accepts an optional `subagentRunnerOptions` per-platform map: `{ "claude-cli": { "model": string?, "effort": string? }, "codex-cli": { "model": string? }, "cursor-cli": { "model": string? } }`; unknown platforms or option keys fail config validation with actionable errors.
- `subagent-review` accepts flat `--subagent-model <value>` and `--subagent-effort <value>` flags that apply **only to the explicitly requested runner** (via `--subagent` or configured `subagentRunner`); fallback runners resolve from `subagentRunnerOptions` alone. Precedence per platform: flag (requested runner only) > config entry > platform default.
- `buildRunnerSpawnCommand` forwards resolved values into each platform's documented flags: `claude --model <m> --effort <e>`, `codex exec -m <m>` (effort via `-c` reasoning override where expressible), `agent --model <m>` (cursor-cli has no effort flag — effort rides the model slug).
- Values a platform cannot express fail fast before spawn (e.g. `--subagent-effort` with `cursor-cli` requested, or an effort entry under `subagentRunnerOptions["cursor-cli"]`) — no silent dropping.
- `SubagentRunnerInvocation` ledger rows gain optional `runnerModel` and `runnerEffort` recording what actually ran (`null`/absent when platform default); recorded for fallback attempts too, from that platform's config entry.
- Docs updated: `docs/template/delivery/delivery-orchestrator.md` (config + flags + precedence), `README.md`, `AGENTS.soa.md`.

## Red

- Write failing tests in `tools/delivery/test/subagent-runner.test.ts` (and config tests):
  - precedence: flag beats config beats default, per platform;
  - spawn-arg construction for all three platforms with model and (where supported) effort resolved;
  - flat flag does not apply to a fallback runner — the fallback attempt resolves from config;
  - invalid effort value and effort-on-cursor-cli fail fast with actionable messages;
  - ledger row records `runnerModel`/`runnerEffort` for an overridden run and absent/null for a default run;
  - config validation rejects unknown platform keys and unknown option keys in `subagentRunnerOptions`.
- Run the test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P21.04): <description> [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Extend config parsing (`tools/delivery/config.ts`), selection resolution (`resolveSubagentSelection` or a sibling resolver), spawn construction, and invocation-row building (`buildRunnerInvocation`) with the smallest change that passes.

## Refactor

- Keep resolution in one function that returns the per-attempt `{model?, effort?}` so the fallback loop (P21.03) consumes it uniformly; no opportunistic cleanup.

## Review Focus

- Both sides of the boundary: the resolver produces values _and_ every spawn path consumes them — check `buildRunnerSpawnCommand` call sites, not just the function.
- Interaction with P21.03: each attempt in the fallback chain must resolve options for _its own_ platform; the requested runner's flag values must not leak into a fallback attempt's spawn args or ledger row.
- Fail-fast placement: validation errors surface before any runner spawns, not mid-chain.
- No model/effort value allowlists — platforms own their model namespaces; we validate shape (non-empty string, known effort tier for claude-cli) not catalog membership.
- Intentionally deferred: auto-selection from diff stats; availability-aware fallback ordering; cross-family enforcement.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
