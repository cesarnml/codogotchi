# P9.02 VS Code (Copilot) native hooks end-to-end

Size: 2 points
Type: feat
Scope: hooks
Red: required

## Outcome

- `classifyEvent` in `packages/cli/src/hook-binary.ts` correctly classifies both Copilot payload dialects to `source_origin: vscode`:
  - camelCase CLI payloads (`toolName`, `toolArgs`, `toolResult`, `sessionId`, `cwd`).
  - VS Code-compatible snake_case payloads with `hook_event_name` (`tool_name`, `tool_input`, `tool_result`).
- Copilot tool names map to existing activity states via a Copilot alias table: `bash`→Shell semantics (test-runner/thinking/implementing split preserved), `create`/`edit`→`implementing`, `view`→`reading`, `grep`/`glob`→`thinking`, `web_fetch`→`reading`, `task`→`thinking`.
- Event→kind mapping: `userPromptSubmitted`→`prompt_submit` (`thinking`), `preToolUse`/`postToolUse`→`tool_use`, `agentStop`/`sessionEnd`→`session_end` (`standby`), `errorOccurred`/`postToolUseFailure`→`errored`, `permissionRequest`→`waiting_for_input`.
- `codogotchi hooks install --platform vscode` writes idempotent hook entries to user-level `~/.copilot/hooks/codogotchi.json` (respecting `COPILOT_HOME`) with `CODOGOTCHI_HOME` + `CODOGOTCHI_ORIGIN=vscode`; `hooks uninstall` removes only codogotchi entries; re-running install produces a byte-identical file.
- `hooksStatus()` reports the `vscode` platform with `installable_in_phase: true` and real `present_on_disk`/`installed`/`partially_installed`/`firing_recently` detection (replacing the current placeholder block).
- Doc-derived stdin samples committed under `packages/engine/test/fixtures/hooks/copilot/`.

## Red

- Add failing classifier tests in `packages/cli/src/hook-binary.test.ts` (inline payloads, matching the existing convention):
  - camelCase `preToolUse` with `toolName: "edit"` + `CODOGOTCHI_ORIGIN=vscode` → `origin: vscode`, state `implementing`.
  - snake_case `hook_event_name: "PreToolUse"`, `tool_name: "view"` → `reading`.
  - `userPromptSubmitted` → `prompt_submit` / `thinking`.
  - `bash` with a test-runner command → `testing`; with a read-only command → `thinking`.
  - `agentStop` → `standby`; `errorOccurred` → `errored`; `permissionRequest` → `waiting_for_input`.
- Add a failing installer/idempotency test (mirroring existing Cursor/Codex install tests with a `CODOGOTCHI_USER_ROOT` temp dir): install twice → identical `~/.copilot/hooks/*.json`; `hooksStatus().vscode.installed === true` after install; `uninstall` leaves no codogotchi entries.
- Run the suite, confirm failures.
- Commit `[red]`: `test(P9.02): vscode copilot classifier + installer idempotency [red]`.

## Green

- Add `"userpromptsubmitted"` to `PROMPT_SUBMIT_TOKENS` (note Copilot's `-ted` suffix vs the existing `userpromptsubmit`).
- Extend `normalize`/`rawHookKind` to read the camelCase Copilot fields (`toolName`/`toolArgs`) as fallbacks alongside the existing `tool_name`/`tool_input`; map Copilot event names (`agentStop`, `errorOccurred`, `postToolUseFailure`) into the existing kind/terminal-state branches.
- Add a Copilot tool-alias resolver feeding the existing state switch (do not assume Claude `Edit`/`Write` names).
- Add `installVscodeHooks`/`uninstallVscodeHooks` in `packages/cli/src/hooks.ts` following the Cursor pattern (user-root config, backup-if-exists, idempotent matcher dedup via `isCodogotchiCommand`); wire `--platform vscode` in the CLI router; replace the placeholder `vscode` block in `hooksStatus()` with real detection.

## Refactor

- If the Copilot alias table and the existing name switch can share a single resolver without behavior change, extract it; otherwise leave the existing platforms untouched.
- Only refactor code this ticket touches.

## Review Focus

- `origin: vscode` is canonical; `CODOGOTCHI_ORIGIN=vscode` (already honored by `rawHookOrigin`) is what the installed command must set — verify the installed hook command string includes it.
- Both payload dialects: confirm a snake_case `hook_event_name` payload and a camelCase payload classify identically.
- Installer idempotency across the full five-platform set (double-install no-dupe); uninstall must not touch non-codogotchi entries.
- Boundary check: the installer writes the command and `hooksStatus` detects it — verify both sides agree on the same file path and command token.
- Real-usage validation (developer, post-merge) is the empirical gate; CI green on doc fixtures is the merge gate.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `camelCase preToolUse with toolName:'edit' classifies as implementing` failed first (toolName not read); `installVscodeHooks` import error failed first for the installer tests.

Why this path: Adding `toolName`/`toolArgs` to `HookInput` + a Copilot alias resolver in `normalize` handles both dialects without duplicating the existing activity-state switch. `CODOGOTCHI_ORIGIN=vscode` env override (already in `rawHookOrigin`) is the disambiguation anchor — no heuristic needed. Copilot hooks file is a simple JSON array written to `~/.copilot/hooks/codogotchi.json`, deduplicated on re-install exactly like the Cursor pattern.

Alternative considered: Adding a Copilot-specific origin-detection heuristic by checking for `toolName` key presence was considered but rejected — Copilot sets `CODOGOTCHI_ORIGIN=vscode` in the installed command, so the env override is both sufficient and explicit, matching the Codex Desktop pattern.

Deferred: repo-level `.github/hooks/` install (documented opt-in only); XP/sync JSONL ingestion; `COPILOT_HOME` env override for alternate Copilot config root (user-level only implemented).

Contract note: `sessionEnd` (Cursor) and `agentStop`/`sessionEnd` (Copilot) now both map to `standby` via the `rawEventName === "agentstop" || rawEventName === "sessionend"` guard. This is a behavioral improvement for Cursor's `sessionEnd` event (previously returned `thinking`); no existing test covered Cursor `sessionEnd`.
