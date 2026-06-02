# P6.06 Cursor hooks installer + bridge docs

Size: 3 points
Type: feat
Scope: cli
Red: required

## Outcome

- `codogotchi hooks install --platform cursor` writes `~/.cursor/hooks.json` calling `codogotchi-hook --platform cursor` for the relevant Cursor hook events (`afterFileEdit`, `beforeShellExecution`, `afterShellExecution`, `stop`, `sessionEnd`).
- `codogotchi hooks install` (no platform flag) installs Claude Code hooks only (existing behavior, unchanged).
- `codogotchi hooks status` reports the detected mode: `bridge` (Cursor with Third-party skills using `~/.claude/settings.json`) or `native` (Cursor with `~/.cursor/hooks.json`), in addition to the existing Claude Code status.
- `codogotchi hooks uninstall --platform cursor` removes the Cursor hook entries from `~/.cursor/hooks.json` without touching Claude Code hooks.
- README/runbook documents both paths and when to prefer each (bridge: simpler, no Cursor restart required; native: correct `source_origin`, shell classification, direct `afterFileEdit` signal).

## Red

- In `packages/cli/src/hooks.test.ts` (or equivalent), add tests:
  - `hooks install --platform cursor` writes `~/.cursor/hooks.json` with the correct entries.
  - `hooks install --platform cursor` is idempotent — running twice does not duplicate entries.
  - `hooks uninstall --platform cursor` removes the Codogotchi entries and leaves any pre-existing entries intact.
  - `hooks status` with `~/.cursor/hooks.json` present and Codogotchi entries → reports `cursor: native`.
  - `hooks status` with `~/.claude/settings.json` containing `codogotchi-hook` entry but no `~/.cursor/hooks.json` → reports `cursor: bridge`.
- Run `bun test` and confirm the new tests fail.
- Commit: `test(P6.06): Cursor hooks installer + status [red]`

## Green

- Add `--platform <claude_code|cursor>` flag to `hooks install` and `hooks uninstall` commands. Default is `claude_code`.
- Implement `installCursorHooks(home: string)`:
  - Read `~/.cursor/hooks.json` if present, parse, merge Codogotchi entries, write back atomically.
  - If absent, write a new `hooks.json` with only the Codogotchi entries.
  - Codogotchi entries cover: `afterFileEdit`, `beforeShellExecution`, `afterShellExecution`, `stop`, `sessionEnd` — each calling `codogotchi-hook` via stdin pipe with the event payload.
- Implement `uninstallCursorHooks(home: string)`: remove only Codogotchi-owned entries, preserve all others.
- In `hooks status`:
  - Check for `~/.cursor/hooks.json` with Codogotchi entries → `cursor: native`.
  - Check for `~/.claude/settings.json` `codogotchi-hook` entry → `cursor: bridge` (inferred — Cursor's Third-party skills forward to Claude Code hooks).
  - If neither → `cursor: not installed`.
- Add runbook section to README: "Cursor install paths" — bridge (no config change needed if Claude Code hooks already installed) vs native (run `codogotchi hooks install --platform cursor`, restart Cursor). Note bridge limitation: `source_origin` will show `claude_code` not `cursor`.

## Refactor

- Extract `readJsonFile` / `writeJsonFileAtomic` helpers if not already present — both Claude Code and Cursor hook installers need idempotent JSON merge.

## Review Focus

- `~/.cursor/hooks.json` format: confirm the exact schema Cursor expects (from hooks docs). The installer must produce a file Cursor can parse — a malformed file silently disables all Cursor hooks.
- Idempotency: running `install` twice must not add duplicate hook entries. Use a Codogotchi-owned key or entry ID to detect existing entries.
- `uninstall` must be surgical — do not clobber user's other Cursor hook entries.
- Bridge detection heuristic (`~/.claude/settings.json` scan) is best-effort; document its limitations in `hooks status` output (e.g. "bridge mode inferred — source_origin may show claude_code").
- Confirm the `--platform cursor` flag name is consistent with how `codogotchi-hook --platform cursor` is invoked in the hook payload.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `hooks install --platform cursor writes ~/.cursor/hooks.json with correct entries` — `installCursorHooks` was a no-op stub, so the file was never created and `readFileSync` threw.
Why this path: Native Cursor hooks give correct `source_origin: "cursor"` and shell classification signals. Bridge path continues to work for users who prefer it — both paths are supported and documented.
Alternative considered: Auto-detect Cursor presence and install native hooks automatically during `codogotchi hooks install` — rejected, modifying `~/.cursor/hooks.json` without explicit `--platform cursor` opt-in is too invasive.
Deferred: VS Code Copilot hook installer — Phase 09. Auto-detection of Cursor Third-party skills state — Phase 07 if needed.
Contract note: `~/.cursor/hooks.json` uses a flat event-name → hook-array map (no `"hooks"` wrapper key, unlike Codex). The command string follows the same `CODOGOTCHI_HOME='...' codogotchi-hook` pattern as Codex. No `--platform cursor` arg is passed to the binary — origin is auto-detected from `hook_event_name` camelCase heuristic (P6.05). Bridge detection is best-effort: `source_origin` will show `"cursor"` for native events but `"claude_code"` in bridge mode.
