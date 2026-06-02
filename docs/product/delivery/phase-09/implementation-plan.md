# Phase 09 — Extended Platform Hooks

> Deliver native Codogotchi hook integration for GitHub Copilot (VS Code agent + CLI) and Google Antigravity, with truthful `source_origin`, per-platform tool classification, platform logo badges, and doc-derived fixture tests.

## Epic

Product plan: [phase-09-extended-platform-hooks.md](../../plans/phase-09-extended-platform-hooks.md)
Draft: [phase-09-extended-platform-hooks.md](../../drafts/phase-09-extended-platform-hooks.md)

## Product contract

When this phase is complete, a developer can run `codogotchi hooks install --platform vscode` or `--platform antigravity` and see the menubar pet animate with the **correct** `source_origin` (`vscode` / `antigravity`, never `claude_code`) and meaningful activity states during real file edits and test runs on those platforms. The animation badge and attention bubble show the correct platform logo for all five supported origins. `hooks install` stays idempotent across five platforms, and a published parity matrix explains native vs bridge paths and why OpenCode is deferred.

## Grill-Me decisions locked

- **Keep both platforms in one phase** → both Copilot and Antigravity publish complete hook schemas with example payloads; adapters are built from docs and validated empirically through real usage, so the old "no code before fixtures" gate is unnecessary.
- **VS Code Agent = Copilot, one surface** → not split; the support language is "VS Code"; adapter normalizes both Copilot payload dialects.
- **Canonical `source_origin: vscode`, `copilot` accepted as alias** → matches support language and the existing `hooksStatus` placeholder key.
- **Both platforms validated by the developer through real usage** → land with doc-derived fixtures + CI green; patch any schema drift post-land; real captures are not a pre-merge blocker.
- **Single-user, no backward-compat** → no bridge detect/warn/migrate code; the `.claude/settings.json` bridge gets a one-line caveat only.
- **Logo badges added as committed scope** → the two supplied SVGs wired into the existing badge component (Claude/Codex/Cursor already done).
- **Antigravity `PostToolUse` = error→`errored`, else neutral; no stepIdx Pre/Post correlation** → `PreToolUse` does all tool classification; correlation machinery dropped as unnecessary for animation.
- **Installer writes user-level config only** (`~/.copilot/hooks/`, `~/.gemini/config/`); repo-level surfaces (`​.github/hooks/`, workspace `.agents/hooks.json`) documented as manual opt-in → matches the existing `homedir()`-rooted install model.
- **4 tickets, stacked** → foundation, VS Code end-to-end, Antigravity end-to-end, docs+retrospective.
- **Retrospective: required** → multi-platform adapter work regresses on schema drift; Antigravity is structurally different (no prompt event, `fullyIdle` terminal, no PostToolUse tool name).

## Ticket Order

1. `P9.01 Platform foundation: origin enum + logo badges`
2. `P9.02 VS Code (Copilot) native hooks end-to-end`
3. `P9.03 Antigravity native hooks end-to-end`
4. `P9.04 Parity matrix, runbook, and retrospective`

## Ticket Files

- `ticket-01-platform-foundation-enum-badges.md`
- `ticket-02-vscode-copilot-hooks.md`
- `ticket-03-antigravity-hooks.md`
- `ticket-04-parity-matrix-runbook-retrospective.md`

## Exit Condition

A reviewer can demonstrate: (1) after `hooks install --platform vscode`, a real Copilot session logs `source_origin: vscode` and shows `implementing`/`running-tests` on a real edit + test command; (2) after `hooks install --platform antigravity`, a real Antigravity session logs `source_origin: antigravity` with correct states and a correct `fullyIdle` terminal; (3) all five `source_origin` values render their correct platform logo in the animation badge and attention bubble; (4) `hooks install` run twice duplicates no entries across five platforms; (5) doc-seeded fixture/classification tests pass in CI without network; (6) the parity matrix is published with OpenCode deferred and the bridge caveat documented.

## CI Baseline

> Baseline recorded: 2026-06-02 — **`bun run verify:quiet` (biome) PASS** (263 files, no fixes). **Test suite could not execute on this machine: system-wide `EMFILE` (file-descriptor exhaustion)** affecting `bun test` even for a single file at `ulimit -n 65536` — an environment condition, not a code regression. **Stop condition for the first ticket:** the `[red]` step requires a runnable suite; resolve the fd exhaustion (e.g. restart the machine / kill leaked watchers) and re-confirm `bun test packages convex` green before starting `P9.01`. Record the clean result here when obtained.

## Review Rules

- Tickets must be merged in order (T01 foundation blocks T02–T04).
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** do not block a ticket; newly introduced failures do.
- The `EMFILE` environment condition above is not a code failure; do not "fix" it inside a ticket — resolve it at the environment level before the red step.

## Explicit Deferrals

- **OpenCode** plugin integration (in-process TypeScript plugins, not shell hooks) — future plugin-SDK phase.
- **Repo-level config surfaces** (`​.github/hooks/`, workspace `.agents/hooks.json`) — documented as manual opt-in; installer writes user-level only.
- **Antigravity policy/injection behaviors** (`decision: deny/ask`, `permissionOverrides`, `PreInvocation`/`PostInvocation` `injectSteps`) — Codogotchi stays observational.
- **XP/sync JSONL ingestion** for Copilot/Antigravity — separate cold-path epic.
- **Cloud sandbox / Managed Agents** hook subsets — document degradation only.
- **RPG phases 10–14** — no dependency.

## Stop Conditions

- The `EMFILE` test-runner condition is unresolved (blocks the red step).
- A platform's real-usage validation reveals the published schema is wrong in a way that changes ticket scope (capture the drift, pause, reconcile).
- Broken CI that cannot be resolved within ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Multi-platform adapter work regresses easily when upstream hook schemas drift, and Antigravity is not "the same adapter pattern" (no prompt event, `Stop.fullyIdle` terminal signal, `PostToolUse` carries no tool name). Capture the build-from-docs + empirical-usage-validation playbook and any Copilot/Antigravity schema churn found during delivery.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-09-extended-platform-hooks-retrospective.md`
