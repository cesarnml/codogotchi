# P6.05 Cursor adapter: origin fix + shell hooks + workspace_roots

Size: 2 points
Type: fix
Scope: hook
Red: required

## Outcome

- `rawHookOrigin` correctly identifies Cursor events: camelCase `hook_event_name` values (e.g. `"afterFileEdit"`, `"beforeShellExecution"`) emit `source_origin: "cursor"` instead of `"claude_code"`.
- `afterFileEdit` hook events → `activity_state: "implementing"`.
- `beforeShellExecution` and `afterShellExecution` hook events → classified via the same Bash 3-bucket path (same as `Bash`/`Shell` tool_use).
- When `CURSOR_PROJECT_DIR` is absent, `workspace_roots[0]` from the Cursor hook payload is used for SoA root resolution.
- `source_event.origin` is `"cursor"` in `state.json` for all of the above.

## Red

- In `packages/cli/src/hook-binary.test.ts`, add tests for `classifyEvent`:
  - `hook_event_name: "afterFileEdit"` → `state === "implementing"`, `sourceEvent.origin === "cursor"`.
  - `hook_event_name: "beforeShellExecution"`, `command: "grep foo"` → `state === "reviewing"`, `sourceEvent.origin === "cursor"`.
  - `hook_event_name: "afterShellExecution"`, `command: "npm install"` → `state === "implementing"`, `sourceEvent.origin === "cursor"`.
  - `hook_event_name: "stop"` (Cursor, lowercase) → `sourceEvent.origin === "cursor"` (not `"claude_code"`).
  - `hook_event_name: "Stop"` (Claude Code, PascalCase) → `sourceEvent.origin === "claude_code"`.
- Add a `runHook` integration test: Cursor `afterFileEdit` event with `workspace_roots: ["/some/path"]` and no `CLAUDE_PROJECT_DIR`/`CODEX_PROJECT_DIR` env → SoA root resolution uses `workspace_roots[0]`.
- Run `bun test` and confirm the new tests fail.
- Commit: `test(P6.05): Cursor origin fix + shell hooks [red]`

## Green

- **`rawHookOrigin` fix:** The current logic returns `"codex"` when `hook_event_name` is all-lowercase, else `"claude_code"`. Cursor events are camelCase (not all-lowercase, not PascalCase). Update the detection:
  - All-lowercase → `"codex"`
  - PascalCase (first char uppercase) → `"claude_code"`
  - camelCase (first char lowercase, contains uppercase) → `"cursor"`
- **`rawHookKind` additions:**
  - `hook_event_name: "afterFileEdit"` → `"tool_use"` (so it flows through the `tool_use` classification path).
  - `hook_event_name: "beforeShellExecution"` / `"afterShellExecution"` → `"tool_use"`.
- **`normalize` additions:**
  - For `afterFileEdit`, set `name = "Edit"` (maps to `implementing` via existing Edit branch).
  - For `beforeShellExecution`/`afterShellExecution`, set `name = "Shell"` (maps to 3-bucket via P6.03).
  - Extract `command` from Cursor's `command` field (already in `HookInput.command`).
- **`workspace_roots` fallback in `runHook`:**
  - Add `workspace_roots?: string[]` to `HookInput`.
  - In `resolveSoaRoot` call, pass `workspace_roots?.[0]` as an additional fallback after `CODEX_PROJECT_DIR` and before `CWD`.

## Refactor

- The origin detection in `rawHookOrigin` is now three branches — add an inline comment explaining the three cases (codex=all-lowercase, claude_code=PascalCase, cursor=camelCase) since this is a non-obvious invariant.

## Review Focus

- The camelCase detection: `eventName[0].toLowerCase() === eventName[0] && eventName !== eventName.toLowerCase()` — verify this correctly identifies camelCase and doesn't false-positive on single-word lowercase events (`"stop"`, `"session_start"`).
- `afterFileEdit` payload from Cursor docs: `{ file_path, edits }` — no `tool_name` field. Confirm `rawHookKind` doesn't fall through to an unexpected kind.
- `beforeShellExecution` fires _before_ the command runs; `afterShellExecution` fires after. Both are valid classification signals. Decide which one to use if both arrive for the same command — or handle both. Document in Rationale.
- `workspace_roots` fallback: SoA root resolution should try `CURSOR_PROJECT_DIR` (if we add it to HookInput) before `workspace_roots[0]`. Check whether `CURSOR_PROJECT_DIR` env var exists in practice.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: The origin misattribution bug (`claude_code` for Cursor events) is a data-quality issue that corrupts `source_origin` in `state-transitions.log`. Fixing it in `rawHookOrigin` is a 3-line change with high diagnostic value.
Alternative considered: Adding explicit `platform: "cursor"` field to HookInput and requiring callers to set it — rejected, would require updating the Cursor hook installer to pass an extra field, coupling installer and binary versions.
Deferred: `CURSOR_PROJECT_DIR` env var support (if Cursor exposes it) — Phase 07. `afterAgentThought` → `thinking` work_mode signal — Phase 07 (confirmed available in Cursor hooks docs: `{ text, duration_ms }`).
Contract note: [fill in during implementation]
