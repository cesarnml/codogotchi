# P5.02 `hooks install | uninstall | status`

Size: 3 points
Type: feat
Scope: hooks
Red: required

## Outcome

- Router exposes `codogotchi hooks install`, `hooks uninstall`, `hooks status` with `--help` for each.
- **`hooks install`:** backup-then-write for `~/.codex/hooks.json` and `~/.claude/settings.json` (timestamped sidecar, e.g. `*.codogotchi-backup-<iso>`); idempotent merge unchanged in spirit from P1.12; **refuses** if `~/.codogotchi/config.json` is missing (message: launch app or run `codogotchi setup`).
- **`hooks uninstall`:** remove Codogotchi hook entries from supported files; leave backup sidecars on disk.
- **`hooks status`:** machine-readable JSON (default when `--json` or stdout for app) and human-readable summary; per-platform: `codex`, `claude_code`, `cursor`, `vscode`, `antigravity` with `present_on_disk`, `installable_in_phase`, `installed`, `firing_recently` (when inferable), `last_event_at`, `source_origin` when available.
- Hook shell commands **omit** `CODOGOTCHI_CONVEX_URL`; Codex command uses `CODOGOTCHI_HOME` + `codogotchi-hook` only.
- Existing `hooks.test.ts` updated; backup files created on install when targets exist.

## Red

- Write failing tests: backup file created before mutate; install refused without config; uninstall removes entries; status JSON shape for installed vs not.
- Write failing test: installed Codex hook command string does not contain `CODOGOTCHI_CONVEX_URL`.
- Commit: `test(P5.02): hooks install uninstall status and backup [red]`.

## Green

- Implement backup helper in `packages/cli/src/hooks.ts`.
- Wire router subcommands; document JSON schema in ticket Rationale or `docs/contracts/` only if needed for app parser.
- Update TOML side effects for Codex as today.

## Refactor

- Extract shared `installHooks` / `uninstallHooks` / `hooksStatus` used by P5.03 `setup` and subprocess callers.
- Do not add Cursor/VS Code/Antigravity install in this ticket.

## Review Focus

- Re-running install is idempotent.
- Backup naming is predictable for support/debug.
- Status JSON stable enough for Swift parser in P5.05.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
