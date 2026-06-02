# Handoff: verify the REAL VS Code / Copilot hook API (live capture)

> **✅ RESOLVED 2026-06-03.** This was carried out and fixed. Findings: the
> write-side file format was wrong (Copilot needs a versioned event-map with a
> `bash` field, not a flat `{hooks:[{event,command}]}` array — that's why it was
> 100% silent). The payload turned out to be Claude-Code-shaped (PascalCase
> `hook_event_name`, snake_case `tool_name`/`tool_input`, `prompt`, `cwd`), so
> the parse side only needed real VS Code tool-name aliases (run_in_terminal →
> Shell, read_file → Read, grep_search → Grep, create_file/insert_edit_into_file
> → Write/Edit) plus `cwd` for repo_root. Kept below as the capture-method
> reference for future platforms.

> Paste this whole file to the next Claude as the task brief. It mirrors the
> Antigravity debug session that fixed commit `316916c`
> (`fix(hooks): classify Antigravity events by payload shape`). The VS Code /
> Copilot adapter has the **same risk profile** and was never verified against
> a real session.

## Why this is needed

Codogotchi's VS Code / Copilot adapter is marked **"documented, not verified"**
in `docs/runbooks/phase-09-platform-parity.md` — built from a published schema +
hand-written fixtures, never confirmed against a live Copilot session. The
Antigravity adapter had the identical pedigree and turned out to be **broken in
the wild**: Antigravity's stdin payload carries **no event-name field**, but the
binary keyed every decision off `input.hook_event_name`, so every event fell
through to `thinking` and the pet got stuck. Assume Copilot may be wrong the
same way until a live capture proves otherwise.

**Do not trust the fixtures. Capture real payloads and let ground truth drive
the fix.** (This repo's user preference: instrument and observe, don't guess —
see `memory/feedback_debug_logging_when_stuck.md`.)

## What the code currently ASSUMES (unverified — what to check)

Parse side — `packages/cli/src/hook-binary.ts`:
- `HookInput` reads camelCase `toolName` and `toolArgs.command` for Copilot.
- Event classification keys off `input.hook_event_name` (snake_case field). The
  Copilot branches match `rawEventName` against `userpromptsubmitted`,
  `agentstop`, `sessionend`, `erroroccurred`, `permissionrequest`,
  `pretooluse`/`posttooluse` (see `normalizedEventToken`, `rawHookKind`,
  `classifyEvent`). **If Copilot does not send an event-name field on stdin
  (or uses a different name/casing), this all fails exactly like Antigravity.**
- Origin is forced via env `CODOGOTCHI_ORIGIN=vscode` (so origin is reliable;
  only the EVENT identity is at risk).
- `resolveCopilotToolAlias` maps tool names: bash→Bash, create/edit→Edit,
  view→Read, grep→Grep, glob→Glob, web_fetch→WebFetch, task→Grep.
- Repo root: `detectRepoRoot` reads Cursor `workspace_roots` and Antigravity
  `workspacePaths`. **Check what field Copilot uses for the workspace dir** (it
  may need adding, like `workspacePaths` did — otherwise repo_root falls back to
  PWD = the IDE launch dir).

Write side — `packages/cli/src/hooks.ts`:
- Writes `~/.copilot/hooks/codogotchi.json` as `{ "hooks": [ { event, command } ] }`.
- `COPILOT_CODOGOTCHI_EVENTS` = userPromptSubmitted, preToolUse, postToolUse,
  agentStop, sessionEnd, errorOccurred, permissionRequest.
- `copilotHookCommand` prepends `CODOGOTCHI_HOME=... CODOGOTCHI_ORIGIN=vscode`.
- **Verify this file path, JSON shape, and event names are what Copilot actually
  reads.** (Antigravity's `Stop` needed a flat list vs nested matcher — Copilot
  may have its own structural quirks.)

## Key facts that make capture easy

- The live hook is `~/.local/bin/codogotchi-hook` → a **symlink to the repo
  source** (`packages/cli/bin/codogotchi-hook.ts`, run via bun). So **source
  edits are live immediately — no rebuild/reinstall needed** to test a fix.
- `codogotchi-hook` is on PATH, so a `tee` wrapper in the hooks file captures
  raw stdin without touching the binary.

## Step 1 — Arm a non-invasive capture

Back up the live config, clear the capture file, and rewrite each hook command
to tag + `tee` raw stdin through to the real hook. The exact live path may be
`~/.copilot/hooks/codogotchi.json` — confirm first with the user / by reading it.

For EACH hook entry's `command`, wrap it like this (one per event so the capture
is labeled):

```
printf '\n===EVENT <EventName>===\n' >> '/Users/cesar/.codogotchi/copilot-capture.jsonl'; tee -a '/Users/cesar/.codogotchi/copilot-capture.jsonl' | CODOGOTCHI_HOME='/Users/cesar/.codogotchi' CODOGOTCHI_ORIGIN=vscode codogotchi-hook
```

Then:
```
cp ~/.copilot/hooks/codogotchi.json ~/.copilot/hooks/codogotchi.json.precapture-bak
: > ~/.codogotchi/copilot-capture.jsonl
```

Background-poll until a turn-ending event lands (adapt the Antigravity watcher):
```
cap=~/.codogotchi/copilot-capture.jsonl
for i in $(seq 1 200); do grep -q "===EVENT" "$cap" 2>/dev/null && tail -1 "$cap" | grep -qi "stop\|sessionEnd\|agentStop\|idle" && break; sleep 3; done
```

## Step 2 — Drive one real Copilot turn

Ask the user to **restart VS Code / Copilot** (hooks are read at launch) and run
a prompt that exercises a tool call + a clean turn end, e.g.:

> Do these three things in order, without asking follow-up questions, then stop:
> (1) run the shell command `ls -la`, (2) read README.md, (3) search the
> codebase for "codogotchi". Then give a one-sentence summary and finish.

## Step 3 — Read ground truth and answer these questions

From `~/.codogotchi/copilot-capture.jsonl`:
1. **Is there an event-name field at all?** What is it called and what casing?
   (`hookEventName`? `event`? none → must infer from shape like Antigravity.)
2. **Tool name field** for pre/post tool events? (`toolName`? `tool_name`?
   nested?) **Tool args / shell command** field?
3. **Pre vs Post discriminator** if there's no event name (Antigravity used the
   presence of an `error` key — Post has it, Pre doesn't).
4. **Turn-end event**: what fires when the turn finishes cleanly? What field
   signals success vs error vs interruption? (Maps to standby / errored.)
5. **Workspace/repo-root field** (for `detectRepoRoot`).
6. Does the **write-side file** (path, `{hooks:[...]}` shape, event names)
   match what Copilot actually loaded? (If hooks never fired at all, the
   write-side schema or path is wrong.)

## Step 4 — Fix, mirroring the Antigravity pattern

- If no event-name field: add an `inferVscodeEventName(input)` in
  `hook-binary.ts` (precedence-ordered, like `inferAntigravityEventName`) and
  synthesize `input.hook_event_name` at the top of `classifyEvent` when
  `rawHookOrigin(input) === "vscode"` and the name is absent.
- Fix any field-name/casing mismatches (tool name, command, workspace, error).
- Correct the write-side schema in `hooks.ts` if Copilot's real format differs.
- Add regression tests in `hook-binary.test.ts` using the **exact captured
  payloads** (see the `describe("real payloads (no hook_event_name field)")`
  block added for Antigravity as the template).
- **Verify end-to-end** by replaying the capture file through the live binary:
  `echo '<payload>' | CODOGOTCHI_HOME=$(mktemp -d) CODOGOTCHI_ORIGIN=vscode codogotchi-hook` then inspect the written `state.json`.

## Step 5 — Restore + gate

- Restore `~/.copilot/hooks/codogotchi.json` from `.precapture-bak`, remove the
  backup, leave the capture file as evidence (or note it).
- `bun run format` → `bun test packages/cli/` → `bun run verify:quiet`.
- `bun run mac:test` if any Swift touched (unlikely for a parse fix).
- Commit on a branch; do not merge without the user's word.

## Reference

- Antigravity fix commit: `316916c` (the working template for this exact task).
- Captured Antigravity payloads: `~/.codogotchi/ag-capture.jsonl`.
- Parity matrix + "documented vs verified" legend:
  `docs/runbooks/phase-09-platform-parity.md`.
