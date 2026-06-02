# Phase 09: Extended Platform Hooks

**Delivery status:** Decomposed — see `docs/product/delivery/phase-09/`. Next step: `/soa preflight phase-09`.

## TL;DR

**Goal:** Give **lite** users native Codogotchi hook integration on the next two agent platforms after Claude Code, Codex, and Cursor — **GitHub Copilot (CLI + VS Code agent)** and **Google Antigravity** — with truthful `source_origin`, per-platform tool-alias classification, platform logo badges, and fixture-driven tests. Both adapters are built from each platform's **published hook schema** and validated empirically through real-world usage.

**Ships:**

- **VS Code / Copilot:** hook installer for `~/.copilot/hooks/` + `.github/hooks/`; adapter normalizing both Copilot payload dialects (camelCase CLI and snake_case `hook_event_name` VS Code-compatible); `source_origin: vscode` (canonical; `copilot` accepted as alias) in contracts + transition log; Copilot tool-alias table (`bash`, `create`, `edit`, `view`, `grep`, `glob`, `web_fetch`, `task`, …); `codogotchi hooks install --platform vscode`; doc-derived fixtures + classification tests
- **Antigravity:** installer for `.agents/hooks.json` (workspace) + `~/.gemini/config/` (user); adapter for PascalCase events / camelCase fields, including **stepIdx Pre/Post correlation** (PostToolUse carries no tool name) and the **`fullyIdle`** terminal signal; `source_origin: antigravity`; Antigravity tool-alias table (`run_command`, `write_to_file`, `replace_file_content`, `view_file`, …); doc-derived fixtures + tests
- **Platform logo badges:** the supplied Antigravity and GitHub Copilot SVGs (`currentColor`, 24×24, single-path) wired into the **existing** badge component — rendered next to the animation badge and inside the attention bubble, keyed by `source_origin` (Claude/Codex/Cursor badges already exist)
- **Installer UX:** per-platform install flags; idempotent across all native platforms; `hooksStatus` flips `vscode` and `antigravity` to installable and reports installed/firing
- **Parity matrix doc:** platform × config path × events × tool names × bridge vs native × support level; OpenCode explicitly deferred (plugin SDK, not shell hooks)

**Defers:**

- **OpenCode** — in-process TypeScript plugins (`tool.execute.before`, `session.idle`, …), not `codogotchi-hook`; separate future plugin-SDK phase
- XP/sync JSONL ingestion for Copilot or Antigravity (hooks-only animation is sufficient this phase)
- Antigravity `PreInvocation`/`PostInvocation` step-injection and `decision`/`permissionOverrides` policy behaviors — Codogotchi stays observational (emits `{}` / `allow`), it does not gate tool calls
- Cloud sandbox / Managed Agents hook subsets (document degradation only)

---

Phases 05–08 established lite install, native Cursor hooks, signal honesty, and the settings-window release gate. Multi-platform hooks are core lite value; RPG phases 10–14 do not block hook parity. Research on 2026-06-02 — corrected against each platform's published hook reference — confirmed that **Copilot** and **Antigravity** both extend the existing shell-hook architecture, while **OpenCode** requires a different (plugin-SDK) integration track. Both Copilot and Antigravity publish complete hook schemas with example stdin payloads, so adapters are built from docs and **validated empirically by the developer through real-world usage**, with any schema drift patched after the phase lands. Codogotchi is single-user, so no bridge backward-compat or migration path is required.

## Phase Goal

This phase should leave the product in a state where:

- A developer using **VS Code / Copilot** with `codogotchi hooks install` sees the pet animate with **`source_origin: vscode`** (never `claude_code`) and meaningful states during file edits and test runs.
- A developer using **Antigravity** with `codogotchi hooks install` sees the pet animate with **`source_origin: antigravity`** and correct tool classification despite PostToolUse carrying no tool name.
- The animation badge and attention bubble show the **correct platform logo** for all five `source_origin` values.
- **`hooks install` is idempotent** across Claude Code, Codex, Cursor, VS Code/Copilot, and Antigravity — running it twice duplicates nothing.
- Operators can read one **parity matrix** explaining native paths, the documented `.claude/settings.json` bridge caveat, and why OpenCode is out of scope.

## Committed Scope

### 1. GitHub Copilot — VS Code agent + CLI (`source_origin: vscode`)

- Register shell hooks invoking `codogotchi-hook` with `CODOGOTCHI_HOME` and `CODOGOTCHI_ORIGIN=vscode` (PascalCase events otherwise classify as `claude_code` under today's heuristic).
- **Config surfaces:** user `~/.copilot/hooks/*.json` (respect `COPILOT_HOME`); repo `.github/hooks/*.json`. Registration JSON uses `{ version: 1, hooks: { <event>: [ { type: "command", … } ] } }`.
- **Events (minimum):** `userPromptSubmitted`, `preToolUse`, `postToolUse`, `agentStop`, `sessionEnd`; add `errorOccurred` / `postToolUseFailure` / `permissionRequest` when confirmed in real usage (`permissionRequest` maps to the existing `waiting_for_input` work).
- **Adapter:** normalize both payload dialects — camelCase CLI (`toolName`, `toolArgs`, `toolResult`) and VS Code-compatible snake_case with `hook_event_name` (`tool_name`, `tool_input`, `tool_result`).
- **Tool-alias table:** map Copilot's **actual CLI tool names** (`bash`, `create`, `edit`, `view`, `grep`, `glob`, `web_fetch`, `task`, `ask_user`) to existing classify heuristics — do **not** assume Claude `Edit`/`Write` or the VS Code-extension names (`create_file`, `replace_string_in_file`).
- **SoA root:** extend project-root resolution using session `cwd` and workspace roots (same pattern as Cursor `workspace_roots`).
- **Fixtures + tests** under `packages/engine/test/fixtures/hooks/copilot/`, seeded from the published reference and refined from real captures.

### 2. Google Antigravity (`source_origin: antigravity`)

- Register shell hooks invoking `codogotchi-hook` with `CODOGOTCHI_ORIGIN=antigravity`.
- **Config surfaces:** workspace `.agents/hooks.json`; user `~/.gemini/config/`. Hook file maps named hooks → events with `enabled` toggle and `matcher` regex.
- **Events:** `PreToolUse`, `PostToolUse`, `Stop` (minimum); `PreInvocation`/`PostInvocation` as the model-call boundary if needed for a `thinking` analog (Antigravity has **no prompt-submit event**).
- **Adapter specifics (net-new vs the Claude/Cursor/Copilot pattern):**
  - PascalCase events, **camelCase fields** (`toolCall.name`, `toolCall.args`, `conversationId`, `stepIdx`, `workspacePaths`).
  - **PostToolUse carries no tool name** — correlate to its PreToolUse by `stepIdx` to classify the tool.
  - **`Stop.fullyIdle`** distinguishes true terminal/standby from "background tasks still running."
  - Codogotchi stays observational: emit `{}` / `decision: "allow"`, never `deny`/`ask`.
- **Tool-alias table:** Antigravity vocabulary (`run_command`, `write_to_file`, `replace_file_content`, `multi_replace_file_content`, `view_file`, `list_dir`, `find_by_name`, `grep_search`, `search_web`, `read_url_content`, `browser_.*`).
- **Fixtures + tests** under `packages/engine/test/fixtures/hooks/antigravity/`, seeded from the published reference and refined from real captures.

### 3. Platform logo badges

- Wire the supplied **Antigravity** and **GitHub Copilot** SVGs (`currentColor`, 24×24, single-path) into the **existing** badge component that already renders Claude/Codex/Cursor.
- Render the logo badge **next to the animation badge** and **inside the attention bubble**, switched on `source_origin` with the existing neutral fallback for unknown origins.

### 4. Installer and status UX

- `codogotchi hooks install --platform vscode` / `--platform antigravity` and `hooks uninstall` symmetry.
- Extend `--all` (or default install) to include the two new platforms; idempotent across all five.
- Flip `vscode` and `antigravity` `installable_in_phase` in `hooksStatus`; report installed/firing.
- Optional: Settings Developer tab lists new platforms' install state (reuse Phase 08 surface if cheap).

### 5. Documentation

- Runbook + README: native VS Code and Antigravity install; one-line `.claude/settings.json` bridge caveat (no migration code — single-user, native install is the path).
- **Platform parity matrix** (committed deliverable): platform × config path × events × tool names × native vs bridge × support level (`verified` vs `documented`).

## Explicit Deferrals

- **OpenCode plugins** — event hooks run in-process (`tool.execute.before`, `session.idle`, …); not an extension of `codogotchi hooks install`. Defer to a future plugin-SDK phase.
- **Antigravity policy/injection behaviors** — `decision: deny/ask/force_ask`, `permissionOverrides`, and `PreInvocation`/`PostInvocation` `injectSteps` are real capabilities but out of scope; Codogotchi observes, it does not gate or inject.
- **Cold-path XP/sync** for Copilot/Antigravity JSONL — separate epic; hook-only delivers lite animation value.
- **Cloud agent sandboxes** with restricted hook subsets — document what degrades; do not block desktop/CLI ship.
- **RPG phases 10–14** — no dependency; this phase is lite-only.

## Exit Condition

A reviewer can demonstrate:

1. **VS Code / Copilot:** after `hooks install --platform vscode`, a real Copilot session (validated by the developer through actual usage) logs `source_origin: vscode`, shows `implementing` / `running-tests` on a real file-edit + test command, and the transition log includes the shell command where applicable.
2. **Antigravity:** after `hooks install --platform antigravity`, a real Antigravity session (validated by the developer through actual usage) logs `source_origin: antigravity` with correct tool classification (stepIdx-correlated) and a correct terminal state from `fullyIdle`.
3. **Logo badges:** all five `source_origin` values render their correct platform logo next to the animation badge and in the attention bubble.
4. **Idempotency:** running `hooks install` twice duplicates no hook entries across five platforms.
5. **CI without network:** doc-seeded fixture/classification tests pass for both new platforms.
6. **Parity matrix** is published, with OpenCode listed as deferred (with rationale) and the bridge caveat documented.

Both new platforms land with doc-seeded fixtures and CI green; the developer exercises each live and reports back; any schema drift is patched after the phase lands. Real captures are not a pre-merge blocker.

## Retrospective

`required` — multi-platform adapter work regresses easily when upstream schemas drift, and Antigravity is **not** "the same adapter pattern" (no prompt event, stepIdx Pre/Post correlation, `fullyIdle` terminal signal). Capture the build-from-docs + empirical-usage-validation playbook and any Copilot/Antigravity schema churn discovered during delivery. Trigger: architecture/process impact + durable-learning risk.
