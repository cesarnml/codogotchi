# P9.03 Antigravity native hooks end-to-end

Size: 2 points
Type: feat
Scope: hooks
Red: required

## Outcome

- `classifyEvent` correctly classifies Antigravity payloads to `source_origin: antigravity`:
  - PascalCase events (`PreToolUse`, `PostToolUse`, `Stop`, optionally `PreInvocation`/`PostInvocation`) with camelCase fields (`toolCall.name`, `toolCall.args`, `conversationId`, `stepIdx`, `workspacePaths`).
  - `CODOGOTCHI_ORIGIN=antigravity` overrides the PascalCase heuristic that would otherwise misclassify as `claude_code`.
- Antigravity tool names map via a dedicated alias table: `run_command`→Shell semantics, `write_to_file`/`replace_file_content`/`multi_replace_file_content`→`implementing`, `view_file`/`read_url_content`→`reading`, `grep_search`/`find_by_name`/`list_dir`→`thinking`, `browser_.*`→`thinking`.
- `PreToolUse` does all tool classification. `PostToolUse` (which carries only `stepIdx` + `error`, no tool name) maps to `errored` when `error` is non-empty, otherwise a neutral `thinking` — **no stepIdx Pre/Post correlation**.
- `Stop` maps to `standby` when `fullyIdle === true`; when `fullyIdle === false` (background tasks still running) it does not assert a terminal/standby state. `terminationReason: "error"` (or non-empty `error`) → `errored`.
- Antigravity has **no prompt-submit event**; `PreInvocation` is the model-call boundary and is optional (only wire it if a `thinking` lead-in is wanted).
- Hook output stays observational: emit `{}` (or `decision: "allow"` for `PreToolUse`); never `deny`/`ask`, never `injectSteps`.
- `codogotchi hooks install --platform antigravity` writes idempotent config to user-level `~/.gemini/config/hooks.json` (named-hook map with `matcher` per the Antigravity schema) setting `CODOGOTCHI_HOME` + `CODOGOTCHI_ORIGIN=antigravity`; uninstall removes only codogotchi entries; re-install is byte-identical.
- `hooksStatus()` reports the `antigravity` platform with real detection (replacing the placeholder block).
- Doc-derived stdin samples committed under `packages/engine/test/fixtures/hooks/antigravity/`.

## Red

- Add failing classifier tests in `packages/cli/src/hook-binary.test.ts`:
  - `PreToolUse` with `toolCall.name: "write_to_file"` + `CODOGOTCHI_ORIGIN=antigravity` → `origin: antigravity`, `implementing`.
  - `PreToolUse` `run_command` with a test-runner `CommandLine` → `testing`; with a read-only command → `thinking`.
  - `PreToolUse` `view_file` → `reading`.
  - `PostToolUse` with `error: ""` → neutral (`thinking`); with `error: "exit status 1"` → `errored`.
  - `Stop` `fullyIdle: true` → `standby`; `terminationReason: "error"` → `errored`.
- Add a failing installer/idempotency test (temp `CODOGOTCHI_USER_ROOT`): double-install identical `~/.gemini/config/hooks.json`; `hooksStatus().antigravity.installed === true`; uninstall leaves no codogotchi entries.
- Run the suite, confirm failures.
- Commit `[red]`: `test(P9.03): antigravity classifier + installer idempotency [red]`.

## Green

- Extend `HookInput`/`normalize` to read `toolCall.name`/`toolCall.args` and the `error`/`fullyIdle`/`terminationReason` fields; route Antigravity event names through the existing kind/terminal branches.
- Add the Antigravity tool-alias resolver. Map `run_command`'s `CommandLine` arg into the existing test-runner/thinking/implementing command split (reuse `matchesTestRunner`/`matchesThinkingCommand`).
- Add `installAntigravityHooks`/`uninstallAntigravityHooks` in `packages/cli/src/hooks.ts` writing the named-hook map schema (`{ "<name>": { "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": ... }] }] } }`); wire `--platform antigravity`; replace the placeholder `antigravity` block in `hooksStatus()`.

## Refactor

- Share the command-classification helpers (`matchesTestRunner`, `matchesThinkingCommand`) between Shell/`run_command` paths without duplicating logic.
- Only refactor what this ticket touches.

## Review Focus

- `PostToolUse` deliberately does **not** correlate to its `PreToolUse` — confirm the neutral/error-only mapping and that no per-conversation tool-state is persisted.
- `fullyIdle: false` must not assert `standby` (background tasks running) — verify it doesn't prematurely rest the pet.
- Observational output only: the hook must never block (`deny`/`ask`) or inject steps.
- Config path is user-level `~/.gemini/config/hooks.json`; workspace `.agents/hooks.json` is documented opt-in (T04), not written here.
- Boundary check: installer command string vs `hooksStatus` detection token agree on path + command.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: stepIdx Pre/Post correlation — rejected; `PreToolUse` already classifies the tool and codogotchi needs no post-completion tool attribution for animation.
Deferred: workspace `.agents/hooks.json` install; `PreInvocation`/`PostInvocation` injection; policy `decision` behaviors; XP/sync JSONL.
Contract note: [any deviation from Type/Scope metadata and why]
