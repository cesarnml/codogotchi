# Platform parity matrix — Phase 09

Codogotchi natively supports five hook-based platforms. This document records
the exact config paths, event set, tool-name mapping, installer flag,
`source_origin`, and support level for each, plus the bridge caveat and
manual repo-level surfaces that are not written by the installer.

---

## Parity matrix

| Platform | Config path(s) | Events | Tool-name surface | Native vs bridge | `source_origin` | Install flag | Support level |
|---|---|---|---|---|---|---|---|
| **Claude Code** | `~/.claude/settings.json` | `UserPromptSubmit` · `PreToolUse` · `PermissionRequest` · `Stop` · `StopFailure` | Native: `Bash`, `Edit`, `Read`, `Write`, `MultiEdit`, `Grep`, `Glob`, `ToolSearch`, `Skill`, `WebSearch`, `WebFetch`, `mcp__*`, `apply_patch` | **Native** | `claude_code` | `hooks install` (default) | **verified** |
| **Codex** | `~/.codex/hooks.json` (primary) · `~/.codex/config.toml` (`features.hooks = true`) · `~/.codex/hooks/codogotchi.toml` (legacy) | `UserPromptSubmit` · `PreToolUse` · `PostToolUse` · `SessionStart` · `PermissionRequest` · `Stop` | PascalCase (same schema as Claude Code); `CODOGOTCHI_ORIGIN=codex` env var distinguishes from claude\_code | **Native** | `codex` | `hooks install` (default) | **verified** |
| **Cursor** | `~/.cursor/hooks.json` | `beforeSubmitPrompt` · `afterFileEdit` · `beforeShellExecution` · `beforeMCPExecution` · `afterShellExecution` · `stop` · `sessionEnd` | Normalized by event: `afterFileEdit`→`Edit`, `beforeShellExecution`/`afterShellExecution`→`Shell`, `beforeMCPExecution`→`MCP`/tool\_name | **Native** (see bridge caveat) | `cursor` | `hooks install --platform cursor` | **verified** |
| **VS Code / Copilot** | `~/.copilot/hooks/codogotchi.json` | `userPromptSubmitted` · `preToolUse` · `postToolUse` · `agentStop` · `sessionEnd` · `errorOccurred` · `permissionRequest` | Copilot camelCase aliases: `bash`→`Bash`, `create`/`edit`→`Edit`, `view`→`Read`, `grep`→`Grep`, `glob`→`Glob`, `web_fetch`→`WebFetch`, `task`→`Grep` | **Native** (see bridge caveat) | `vscode` | `hooks install --platform vscode` | **documented** |
| **Antigravity** | `~/.gemini/config/hooks.json` | `PreToolUse` · `PostToolUse` · `Stop` | Antigravity names (PreToolUse only): `run_command`→`Shell`, `write_to_file`/`replace_file_content`/`multi_replace_file_content`→`Edit`, `view_file`/`read_url_content`→`Read`, `grep_search`/`find_by_name`/`list_dir`→`Grep`, `browser_*`→`Grep`; PostToolUse carries no tool name | **Native** | `antigravity` | `hooks install --platform antigravity` | **documented** |
| **OpenCode** | N/A | N/A | N/A | N/A — uses in-process TypeScript plugins, not shell hooks | N/A | — | **deferred** |

> **Support levels:** `verified` = confirmed via real agent sessions with live event capture; `documented` = adapter built from published hook schema with doc-derived fixture tests; `deferred` = integration not yet built.

---

## Antigravity structural differences

Antigravity is not "the same adapter pattern" — it departs from the other platforms in three ways:

1. **No prompt-submit event.** There is no `userPromptSubmit`/`beforeSubmitPrompt` equivalent. Codogotchi first transitions from the previous state when `PreToolUse` fires.
2. **`fullyIdle` terminal signal on `Stop`.** `Stop { fullyIdle: true }` is the clean-finish edge; `Stop { fullyIdle: false }` means background tasks are still running — the pet maps to `thinking`, not `standby`, in that case. `terminationReason: "error"` or a non-empty `error` string maps to `errored`.
3. **`PostToolUse` carries no tool name.** The `stepIdx` Pre/Post correlation machinery was dropped as unnecessary. `PreToolUse` does all tool classification; `PostToolUse` resolves to `thinking` (or `errored` on a non-empty `error` field).

---

## VS Code / Copilot: `vscode` vs `copilot` alias

The canonical `source_origin` is **`vscode`** — this matches the support language ("VS Code") and the `hooksStatus` key used in `codogotchi hooks status`. The hook binary also accepts `copilot` as a `CODOGOTCHI_ORIGIN` alias for compatibility with manual overrides, but the installer always writes `CODOGOTCHI_ORIGIN=vscode`.

---

## Bridge caveat

VS Code may animate via the Claude Code bridge if Claude Code hooks are installed but native VS Code hooks are not — events then fire with `source_origin: claude_code` (mislabeled). Prefer native: `hooks install --platform vscode`. The same applies to Cursor (pre-Phase 06 bridge path). No detect/migrate code exists for single-user installs; the bridge is a side-effect, not a supported mode.

---

## Repo-level config surfaces (manual opt-in)

The installer writes **user-level** config only (`~/.copilot/hooks/`, `~/.gemini/config/`, etc.). The following repo-level surfaces exist in some platforms but are **not** written by `hooks install` and require manual configuration:

| Surface | Platform | Notes |
|---|---|---|
| `.github/hooks/` | GitHub Copilot (enterprise) | Per-repo hook policy; not written by installer |
| workspace `.agents/hooks.json` | Codex (future) | Workspace-scoped hook file; installer uses `~/.codex/hooks.json` |

These are documented here as manual opt-in only. The installer will not gain repo-level write capability unless a future ticket explicitly adds it.

---

## OpenCode — deferred

OpenCode uses an **in-process TypeScript plugin** model rather than shell hooks. Codogotchi's hook binary is a shell command invoked on lifecycle events; this mechanism does not exist in OpenCode's current public API. Integration is deferred to a future plugin-SDK phase once OpenCode publishes a stable external plugin surface.

---

## Install quick-reference

```bash
# All five native platforms in one call each:
codogotchi hooks install                      # Claude Code + Codex (default)
codogotchi hooks install --platform cursor    # Cursor
codogotchi hooks install --platform vscode    # VS Code / GitHub Copilot
codogotchi hooks install --platform antigravity  # Google Antigravity

# Check install + firing status:
codogotchi hooks status

# Remove all hooks for all platforms:
codogotchi hooks uninstall
```

---

_Written: 2026-06-02. Phase 09 delivers native hooks for VS Code (Copilot) and Antigravity alongside the existing Claude Code, Codex, and Cursor platforms._
