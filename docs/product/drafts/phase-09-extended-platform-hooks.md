# Phase 09 Draft — Extended Platform Hooks

_Drafted: 2026-05-27_
_Updated: 2026-06-02 — bumped from Phase 14; platform research findings incorporated_
_Status: Product plan written — [phase-09-extended-platform-hooks.md](../plans/phase-09-extended-platform-hooks.md) awaiting approval; then `/soa decompose`_
_Source: [codogotchi-platform-extension-and-signal-pipeline-research.md](../../notes/public/codogotchi-platform-extension-and-signal-pipeline-research.md) §2.2–2.3, [multi-platform-hook-support.md](../../notes/public/multi-platform-hook-support.md)_

---

## Thesis

After **Cursor** (Phase 06) and the **Phase 08 lite v1 release gate**, expand **lite** install to **GitHub Copilot CLI / VS Code Agent** and **Antigravity 2.0** using the same adapter pattern already proven for Claude Code, Codex, and Cursor: shell `codogotchi-hook` invocations, truthful `source_origin`, tool alias tables, fixture-driven tests. **Copilot ships first** (largest audience, best-documented hook surface, partial bridge may already exist via `.claude/settings.json`). **Antigravity ships only after captured real stdin fixtures.**

**OpenCode is out of scope for this phase.** OpenCode uses in-process TypeScript plugins (`tool.execute.before`, `session.idle`, …), not spawned shell hooks — a different integration track (npm/local plugin), not an extension of `codogotchi hooks install`.

---

## Why Phase 09 (now, not Phase 14)

| Factor | Rationale |
| --- | --- |
| **Lite product goal** | Multi-platform hooks are core lite value; RPG phases (old 09–13, now 10–14) do not block hook parity |
| **Architecture reuse** | `packages/cli/src/hooks.ts` + `hook-binary.ts` already normalize Claude / Codex / Cursor dialects; Copilot is the next shell-hook platform |
| **Partial bridge today** | Copilot reads `.claude/settings.json` — users who ran `codogotchi hooks install` may already see animation mislabeled as `claude_code` (same Cursor bridge pattern pre–Phase 06) |
| **Audience** | Among Antigravity / Copilot / OpenCode, Copilot CLI + VS Code Agent has the broadest install base after the three platforms already shipped |

---

## Platform fit (research summary, 2026-06-02)

Codogotchi’s integration model: platform spawns **`codogotchi-hook`** → JSON **stdin** → classify → write `~/.codogotchi/state.json` → menubar polls. Installers idempotently wire config files under `packages/cli/src/hooks.ts`.

| Platform | Hook model | Natural extension? | Priority in Phase 09 |
| --- | --- | --- | --- |
| **GitHub Copilot CLI / VS Code Agent** | Shell `command` hooks; `{ version: 1, hooks: { preToolUse, … } }`; JSON stdin/stdout; also reads `.claude/settings.json` | **Yes — primary target** | **1 — ship first** |
| **Google Antigravity 2.0** | Shell `command` hooks; PascalCase events (`PreToolUse`, `Stop`); JSON stdin/stdout; tool names alien (`run_command`, `write_to_file`) | **Yes — second** | **2 — fixtures gate** |
| **OpenCode** | TypeScript plugin modules in `.opencode/plugins/` or npm | **No — different track** | **Deferred** (future plugin-SDK phase) |

### Copilot ↔ existing classifier mapping

| Copilot event | Codogotchi use (existing logic) |
| --- | --- |
| `userPromptSubmitted` | `thinking` (like `UserPromptSubmit` / `beforeSubmitPrompt`) |
| `preToolUse` / `postToolUse` | Tool boundary classification |
| `agentStop` | Turn complete → `standby` / terminal |
| `sessionEnd` / `errorOccurred` | Session boundary / `errored` |
| `postToolUseFailure` | Already handled for Cursor |

Copilot supports **two payload dialects** (camelCase CLI vs PascalCase VS Code-compatible with `hook_event_name` + snake_case fields). The adapter must handle both; prefer explicit `CODOGOTCHI_ORIGIN=copilot` in the hook command (same escape hatch as Codex Desktop).

**Config paths to install:**

- User: `~/.copilot/hooks/*.json` (or `$COPILOT_HOME/hooks/`)
- Repo: `.github/hooks/*.json`
- Bridge (document, do not rely on): `.claude/settings.json` (already wired by Phase 05)

**References:** [Using hooks with GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks), [Copilot hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference)

### Antigravity ↔ existing classifier mapping

| Antigravity event | Notes |
| --- | --- |
| `PreToolUse` / `PostToolUse` | PascalCase like Claude — would misclassify as `claude_code` without `CODOGOTCHI_ORIGIN=antigravity` |
| `Stop` | Turn termination; supports `decision: "continue"` (observational only for codogotchi) |
| `PreInvocation` / `PostInvocation` | Optional; inject steps — skip unless needed for animation |

**Tool vocabulary is entirely different:** `run_command` (not `Bash`), `write_to_file` / `replace_file_content` (not `Write`/`Edit`), `view_file` (not `Read`). Requires a dedicated alias table after fixtures land.

**Config paths (document in plan):** workspace `.agents/hooks.json`, user `~/.gemini/config/` (per [Antigravity hooks docs](https://antigravity.google/docs/hooks)).

**Risk:** newest surface; schema and config paths less battle-tested than Copilot. **No adapter code until fixtures exist.**

---

## The problem

- **Copilot tool names differ from Claude** (`create_file`, `replace_string_in_file`, …) — copy-paste Claude heuristics yields idle/wrong states during real work.
- **Copilot may already fire hooks** via the Claude bridge with **`source_origin: claude_code`** — same mis-label bug Cursor had before Phase 06.
- **Antigravity hook shape is research-only**; Gemini CLI sunset increases urgency to capture fixtures before betting schema.
- **`hooksStatus` placeholders** already exist for `vscode` / `antigravity` with `installable_in_phase: false` — Phase 09 flips Copilot first, then Antigravity when fixtures land.
- **OpenCode** looks hook-like in event names but is a plugin SDK — out of scope; document explicitly to avoid scope creep.

---

## Committed scope

### 1. GitHub Copilot CLI / VS Code Agent hooks (ship first)

- Installer for documented hook config paths (`~/.copilot/hooks/`, `.github/hooks/`)
- Hook command sets `CODOGOTCHI_HOME` + `CODOGOTCHI_ORIGIN=copilot` (or `vscode` — pick one canonical origin in contracts; document alias)
- `source_origin: copilot` in contracts + transition log
- Tool alias table: Copilot/VS Code names → classify heuristics (`create_file`, `replace_string_in_file`, …)
- Event normalization: camelCase (`preToolUse`) and VS Code-compatible PascalCase (`PreToolUse` + `hook_event_name`)
- `cwd` / session payload → SoA project root resolution (extend `resolveSoaRoot()` beyond `CLAUDE_PROJECT_DIR`, `CODEX_PROJECT_DIR`, `workspace_roots`)
- Fixture capture + tests under `packages/engine/test/fixtures/hooks/copilot/`
- `codogotchi hooks install --platform copilot` (or `--all` including existing platforms)
- Flip `vscode.installable_in_phase` / status detection in `hooksStatus`

**Minimum events to register:** `userPromptSubmitted`, `preToolUse`, `postToolUse`, `agentStop`, `sessionEnd` (+ `errorOccurred` / `postToolUseFailure` if available in fixtures).

### 2. Google Antigravity 2.0 (fixtures gate)

- `packages/engine/test/fixtures/hooks/antigravity/*.json` from real sessions **before** adapter merge
- Adapter + installer only after fixtures land
- `CODOGOTCHI_ORIGIN=antigravity`; tool alias table for Antigravity tool names
- Config installer for `.agents/hooks.json` / user gemini config path (confirm in plan from fixtures)
- Document IDE vs CLI (`agy`) vs SDK parity matrix

### 3. Installer UX

- `codogotchi hooks install --all` or per-platform flags (`claude_code`, `codex`, `cursor`, `copilot`, `antigravity`)
- Settings → Developer or Hooks section lists installed platforms (optional; may reuse Phase 08 Developer tab)

### 4. Parity matrix doc

- Table: platform × config path × events × tool names × bridge vs native × Codogotchi support level
- Explicit row: **OpenCode** = plugin SDK, not shell hooks, deferred

---

## Defers

- **OpenCode** plugin integration (`.opencode/plugins/` npm/local module) — separate future phase
- Managed Agents API / cloud Copilot sandbox hooks (subset of events; ephemeral sandbox — document degradation)
- Managed Agents API / cloud Antigravity policy hooks (different shape from lifecycle stdin hooks)
- Tab hooks / non-agent Cursor events unless needed for animation
- XP/sync JSONL ingestion for Copilot or Antigravity (hooks-only still valuable; cold path is a later epic)

---

## Exit conditions

1. Copilot CLI or VS Code Agent session produces `source_origin: copilot` (not `claude_code`) and sensible `activity_state` on file edit + test run.
2. `hooks install` idempotent across **five** native platforms (Claude, Codex, Cursor, Copilot, Antigravity when fixtures land).
3. Antigravity fixture tests pass classification without network (after fixtures captured).
4. Parity matrix doc published; bridge path (`.claude/settings.json`) documented with “prefer native install” guidance.
5. OpenCode explicitly listed as deferred with rationale.

---

## Dependencies

- **Phase 05** `hooks install` baseline
- **Phase 06** adapter patterns + attention contract + native Cursor installer
- **Phase 07** global gates (optional; works per-platform once hooks fire)
- **Phase 08** lite v1 release gate (recommended sequencing anchor — ship multi-platform lite story after settings/bundling)

**Does not depend on:** RPG phases (10–14 in updated ladder).

---

## Suggested ticket split (for `/soa decompose`)

| # | Focus |
| --- | --- |
| 1 | Copilot fixture capture + adapter + origin/tool aliases + tests |
| 2 | Copilot installer + `hooksStatus` + `--platform copilot` / `--all` |
| 3 | Antigravity fixture capture (may start in parallel with ticket 1) |
| 4 | Antigravity adapter + installer (blocked on ticket 3 fixtures) |
| 5 | Parity matrix doc + runbook row + bridge vs native guidance |

---

## Next step

1. **Approve** [product plan](../plans/phase-09-extended-platform-hooks.md)
2. `/soa decompose docs/product/plans/phase-09-extended-platform-hooks.md`
