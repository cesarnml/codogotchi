# Phase 09: Extended Platform Hooks

**Delivery status:** Product plan draft — awaiting developer approval before `/soa decompose`.

## TL;DR

**Goal:** Give **lite** users native Codogotchi hook integration on the next two major agent platforms after Claude Code, Codex, and Cursor — **GitHub Copilot CLI / VS Code Agent** first, **Google Antigravity 2.0** second — with truthful `source_origin`, tool-alias classification, and fixture-driven tests. Stop relying on the Claude bridge for Copilot sessions that today mislabel as `claude_code`.

**Ships:**

- **Copilot (primary):** hook installer for `~/.copilot/hooks/` and `.github/hooks/`; adapter for camelCase + VS Code-compatible stdin dialects; `source_origin: copilot` in contracts and transition log; tool alias table for Copilot-specific tool names; `codogotchi hooks install --platform copilot` (and `--all`); fixtures + classification tests
- **Antigravity (fixtures-gated):** real stdin fixtures captured from operator sessions; adapter + installer only after fixtures land; `source_origin: antigravity`; Antigravity tool alias table; config paths confirmed from fixtures
- **Installer UX:** per-platform install flags; `hooksStatus` marks Copilot installable and reports installed/firing
- **Parity matrix doc:** platform × config path × events × bridge vs native × support level; OpenCode explicitly deferred (plugin SDK, not shell hooks)

**Defers:**

- **OpenCode** — in-process TypeScript plugins, not `codogotchi-hook`; separate future phase
- XP/sync JSONL ingestion for Copilot or Antigravity (hooks-only animation is sufficient for this phase)
- Cloud Copilot sandbox / Managed Agents API hook subsets (document degradation only)
- Antigravity SDK policy hooks (`deny`/`allow`) — different shape from lifecycle stdin hooks

---

Phases 05–08 established lite install, Cursor native hooks, signal honesty, and the settings-window release gate. Multi-platform hooks are core lite value; RPG work (HUD, health, loot) does not block hook parity. Research (2026-06-02) compared Antigravity, Copilot CLI, and OpenCode: only **Copilot** and **Antigravity** extend the existing shell-hook architecture; **OpenCode** requires a different integration track.

Copilot may already animate the pet today via **`.claude/settings.json`** (same bridge pattern Cursor had pre–Phase 06) but logs **`source_origin: claude_code`**. Phase 09 makes Copilot **first-class** before Antigravity because Copilot has the largest audience among the remaining platforms, stable hook reference docs, and event names that map cleanly onto the classifier built for Claude/Cursor/Codex.

## Phase Goal

This phase should leave the product in a state where:

- A developer using **Copilot CLI or VS Code Agent** with `codogotchi hooks install` sees the pet animate with **`source_origin: copilot`** (never `claude_code` for native-wired events) and meaningful states during file edits and test runs.
- **`hooks install` is idempotent** across Claude Code, Codex, Cursor, Copilot, and (when fixtures exist) Antigravity.
- **Antigravity** classification is covered by committed fixtures and unit tests — no network, no schema guessing.
- Operators can read one **parity matrix** that explains bridge vs native paths and why OpenCode is out of scope.

## Committed Scope

### 1. GitHub Copilot CLI / VS Code Agent (ship first)

- Register shell hooks that invoke `codogotchi-hook` with `CODOGOTCHI_HOME` and **`CODOGOTCHI_ORIGIN=copilot`** (PascalCase Copilot events otherwise classify as `claude_code` under today’s heuristic).
- **Config surfaces:** user `~/.copilot/hooks/*.json` (respect `COPILOT_HOME`); repo `.github/hooks/*.json`.
- **Events (minimum):** `userPromptSubmitted`, `preToolUse`, `postToolUse`, `agentStop`, `sessionEnd`; add `errorOccurred` / `postToolUseFailure` when fixtures confirm availability.
- **Adapter:** normalize both camelCase CLI payloads and VS Code-compatible payloads (`hook_event_name` + snake_case fields per [Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference)).
- **Tool alias table:** map Copilot/VS Code tool names (`create_file`, `replace_string_in_file`, …) to existing classify heuristics — do not copy-paste Claude `Edit`/`Write` assumptions.
- **SoA root:** extend project-root resolution using session `cwd` and any workspace roots in payload (same pattern as Cursor `workspace_roots`).
- **Fixtures + tests** under `packages/engine/test/fixtures/hooks/copilot/`.
- **Document bridge:** Copilot reads `.claude/settings.json`; native install is preferred; bridge may still mislabel until native hooks fire.

### 2. Google Antigravity 2.0 (fixtures gate — no adapter merge before fixtures)

- Capture real stdin from IDE and/or CLI (`agy`) sessions; commit under `packages/engine/test/fixtures/hooks/antigravity/`.
- **Only after fixtures:** adapter, installer, `CODOGOTCHI_ORIGIN=antigravity`, tool aliases for Antigravity names (`run_command`, `write_to_file`, `view_file`, …).
- Confirm config paths from fixtures (documented candidates: workspace `.agents/hooks.json`, user `~/.gemini/config/` per [Antigravity hooks](https://antigravity.google/docs/hooks)).
- **Parity matrix row:** IDE vs CLI vs SDK — which surfaces fire lifecycle hooks vs policy-only hooks.

### 3. Installer and status UX

- `codogotchi hooks install --platform copilot` and `hooks uninstall` symmetry.
- Extend `--all` (or default install) to include Copilot when not already present.
- Flip **`copilot` / `vscode` `installable_in_phase`** in `hooksStatus` (pick **one** canonical `source_origin` enum value in contracts — recommend **`copilot`**; document VS Code Agent as the same integration surface).
- Optional: Settings Developer tab lists Copilot/Antigravity install state (reuse Phase 08 surface if cheap).

### 4. Documentation

- Runbook + README: native Copilot install, bridge caveat, Antigravity fixture requirement.
- **Platform parity matrix** (committed deliverable, not optional appendix).

## Explicit Deferrals

- **OpenCode plugins** ([OpenCode plugins docs](https://opencode.ai/docs/plugins/)): event hooks run in-process (`tool.execute.before`, `session.idle`, …). Not an extension of `codogotchi hooks install`. Defer to a future **plugin-SDK** phase (npm or `.opencode/plugins/` module).
- **Cold-path XP/sync** for Copilot or Antigravity JSONL — separate epic; hook-only still delivers lite animation value.
- **Cloud agent sandboxes** with restricted hook subsets — document what degrades; do not block desktop/CLI ship.
- **RPG phases 10–14** — no dependency; this phase is lite-only.

## Exit Condition

A reviewer can demonstrate:

1. **Copilot:** after `hooks install --platform copilot`, a Copilot CLI or VS Code Agent session logs **`source_origin: copilot`**, shows `implementing` (or `running-tests`) on a real file-edit + test command, and transition log includes the shell command string where applicable.
2. **Idempotency:** running `hooks install` twice does not duplicate hook entries across five platforms.
3. **Antigravity:** fixture tests pass in CI without network; manual runbook attestation that real sessions produced the fixtures.
4. **Parity matrix** is published and lists OpenCode as deferred with rationale.
5. **Bridge documented:** user on Copilot-with-only-`.claude/settings.json` understands mis-label risk and how to switch to native hooks.

## Retrospective

`required` — multi-platform adapter work is easy to regress when upstream hook schemas drift; retrospective should capture fixture-capture playbook and any Copilot/Antigravity doc churn discovered during delivery.
