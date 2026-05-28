# P6.03 Hook: Bash 3-bucket heuristic + Cursor Shell normalization

Size: 2 points
Type: feat
Scope: hook
Red: required

## Outcome

- `classifyEvent` maps Bash commands to three buckets instead of two:
  - `grep`, `find`, `rg`, `ls`, `cat`, `head`, `tail`, `wc`, `awk`, `sed`, `jq` (and their common flags) → `reviewing`
  - `git push` → `pushing` (unchanged)
  - Test runners → `running-tests` (unchanged)
  - Any other Bash command → `implementing` (previously `idle`)
- Cursor `Shell` tool events follow the identical classification path as `Bash` — no separate branch.
- A Bash call with no command string (command is `undefined`) → `implementing` (previously `idle`).

## Red

- In `packages/cli/src/hook-binary.test.ts`, add tests for:
  - `grep "foo" bar.ts` → `reviewing`
  - `find . -name "*.ts"` → `reviewing`
  - `rg pattern` → `reviewing`
  - `ls -la` → `reviewing`
  - `cat README.md` → `reviewing`
  - `jq '.foo' file.json` → `reviewing`
  - `npm install` → `implementing` (previously `idle`)
  - `bun run build` → `implementing` (previously `idle`)
  - `echo "hello"` → `implementing` (previously `idle`)
  - Bash with `command: undefined` → `implementing` (previously `idle`)
  - Cursor `Shell` tool with `grep` command → `reviewing`
  - Cursor `Shell` tool with `npm install` → `implementing`
- Run `bun test` and confirm the new tests fail.
- Commit: `test(P6.03): Bash 3-bucket + Cursor Shell normalization [red]`

## Green

- Add `REVIEWING_BASH_PREFIXES` constant covering the read-only command set.
- Add `matchesReviewingCommand(command: string): boolean` using the same prefix-match pattern as `matchesTestRunner`.
- In `classifyEvent`, for `name === "Bash"` or `name === "Shell"`:
  - If `command === undefined`: return `implementing`.
  - If `matchesTestRunner(command)`: return `running-tests` (unchanged).
  - If `command.trimStart().startsWith("git push")`: return `pushing` (unchanged).
  - If `matchesReviewingCommand(command)`: return `reviewing`.
  - Else: return `implementing`.
- The `Shell` branch is not a separate `if` — normalize `name === "Shell"` into the same block as `name === "Bash"`.

## Refactor

- The existing `if (name === "Bash" && command !== undefined)` guard can be simplified — `command` being `undefined` now has a defined outcome (`implementing`), so the outer guard becomes unnecessary. Flatten the conditional.

## Review Focus

- Prefix matching must be word-boundary safe: `"catfish"` must not match the `cat` bucket. Verify the `matchesReviewingCommand` implementation uses the same trailing-char check as `matchesTestRunner`.
- `rg` (ripgrep) is a common alias — confirm it's in the reviewing set.
- Cursor `Shell` tool name: confirm via Cursor hooks docs that the tool_name is exactly `"Shell"` (case-sensitive). If it differs, document in Rationale.
- The `undefined` command case returning `implementing` rather than `idle` is a deliberate policy change — reviewer should confirm this is acceptable for unknown commands.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: Extending the existing `classifyEvent` with a third bucket requires no architectural change — same prefix-match pattern already used for test runners. Cursor Shell normalization is zero extra branches by using the same code path.
Alternative considered: Separate `classifyShell` function for Cursor — rejected, identical logic with different name is dead weight.
Deferred: Detecting `awk`/`sed` used for in-place file edits (which could be `implementing`) — deferred as edge case. Phase 07 can refine if the 3-bucket heuristic proves too coarse.
Contract note: [fill in during implementation]
