# Multi-Platform Hook Support — Cursor, Antigravity, VS Code

_Expanded discussion as of 2026-05-25_
_Status: Draft — not yet through `/soa plan`_
_Cross-reference: [Phase 04–05 roadmap](./codogotchi-phase-04-05-roadmap.md), [codogotchi-alignment-draft](../../.son-of-anton/notes/public/codogotchi-alignment-draft.md)_

---

## Recommendation

Treat this as a real product phase, not a config-only tweak. Hook registration is the easy part (~20%). The work is **normalizing four different stdin dialects**, **mapping alien tool names**, **resolving project roots for SoA**, and **accepting uneven CLI vs desktop coverage** — especially Cursor CLI and Antigravity's brand-new surface.

---

## What "same level of support" actually means

Today codogotchi supports **two layers** for Claude + Codex:

| Layer | What it does |
| --- | --- |
| **Animation (hot path)** | Platform fires hook → `codogotchi-hook` → `~/.codogotchi/state.json` → menubar pet |
| **Progression (cold path)** | `codogotchi sync` reads Claude/Codex JSONL → XP/HP/loot in Convex |

"Same level" for Cursor / Antigravity / VS Code means **both** if you want parity. Hook-only gets you Mali animating; it does **not** get XP credit unless you also find activity logs to ingest.

---

## What we already have (reusable)

The core is platform-agnostic once input is normalized:

- One binary: `codogotchi-hook` reads JSON stdin, classifies, merges SoA tail, writes `state.json`
- Loose `HookInput` type with optional explicit `{ origin, kind, name, command }` escape hatch
- Installer pattern in `packages/cli/src/hooks.ts` (write config, idempotent, dedupe)
- Fixture capture recipe in `scripts/capture-hook-fixtures.sh`

**But** the classifier is still Claude/Codex-shaped:

- `rawHookOrigin()` — lowercase `hook_event_name` → `codex`; everything else → `claude_code`
- Tool heuristics hardcode Claude names: `Edit`, `Write`, `Bash`, `Read`
- SoA root resolution only knows `CLAUDE_PROJECT_DIR`, `CODEX_PROJECT_DIR`, and cwd
- Origins in the contract are closed to `claude_code | codex | soa | sync | manual`

Key files:

| Path | Role |
| --- | --- |
| `packages/cli/bin/codogotchi-hook.ts` | Stdin entrypoint |
| `packages/cli/src/hook-binary.ts` | Classify, SoA merge, state write |
| `packages/cli/src/hooks.ts` | Platform hook config installer |
| `packages/engine/src/sources/soa.ts` | SoA path + tail read |
| `packages/contracts/src/state-json.ts` | Output schema + origin enum |
| `scripts/capture-hook-fixtures.sh` | Fixture capture recipe |

---

## Current platform support

### Claude Code (desktop + CLI)

| Dimension | Detail |
| --- | --- |
| **Config** | `~/.claude/settings.json` |
| **Events** | `PreToolUse`, `Stop` |
| **Hook command** | Bare `codogotchi-hook` |
| **Event casing** | PascalCase (`PreToolUse`, `Stop`) |
| **Project dir** | `$CLAUDE_PROJECT_DIR` |
| **Tool names** | `Edit`, `Write`, `MultiEdit`, `Bash`, `Read` |

### Codex (desktop + CLI)

| Dimension | Detail |
| --- | --- |
| **Config** | `~/.codex/hooks.json` (+ legacy TOML) |
| **Events** | `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop` |
| **Hook command** | Env-prefixed: `CODOGOTCHI_HOME=… CODOGOTCHI_CONVEX_URL=… codogotchi-hook` |
| **Event casing** | snake_case (`pre_tool_use`, `session_end`) |
| **Project dir** | `$CODEX_PROJECT_DIR` |
| **Tool names** | Same as Claude (`Edit`, `Bash`, etc.) but different `tool_input` shape |

---

## Per-platform: what's involved

### Cursor (IDE + `cursor-agent` CLI)

**Config:** `~/.cursor/hooks.json` or `.cursor/hooks.json` — same JSON-over-stdio model.

**Why it's not plug-and-play:**

1. **Different field names/shapes**
   - `hook_event_name`: `preToolUse`, `postToolUse`, `stop` (camelCase)
   - `tool_name`: `Shell`, not `Bash`; file ops aren't `Edit`/`Write`
   - Project root: `workspace_roots[]`, not `CLAUDE_PROJECT_DIR`
   - Shell command lives in `tool_input.command` (similar) but many events use `afterFileEdit` instead of tool-use with familiar names

2. **Origin detection breaks today** — `preToolUse` is not all-lowercase, so Cursor would be mislabeled `claude_code`.

3. **CLI parity gap** — Cursor CLI historically fires a **subset** of hooks (shell + some tool events; `afterAgentResponse` etc. still missing or flaky). IDE ≠ CLI for animation quality.

4. **Stdout contract** — Cursor hooks can return JSON (`permission`, etc.). Codogotchi must exit 0 and emit valid passthrough output even when observational-only.

5. **SoA path** — extend `resolveSoaRoot()` to prefer `workspace_roots[0]` (or explicit `CURSOR_PROJECT_DIR` if injected in the hook command).

**Minimum events to register:** `preToolUse`, `postToolUse`, `beforeShellExecution`, `afterShellExecution`, `beforeReadFile`, `afterFileEdit`, `stop`.

**Reference:** [Cursor hooks docs](https://cursor.com/docs/hooks)

---

### VS Code (GitHub Copilot agent hooks — preview)

**Config:** `.github/hooks/*.json`, `~/.copilot/hooks/`, also reads `.claude/settings.json`.

**Why it's not plug-and-play:**

1. **Another stdin dialect** — docs use `hookEventName` (camelCase) _and_ Claude-compatible formats depending on path. VS Code explicitly warns: tool names differ (`create_file`, `replace_string_in_file` vs Claude's `Write`/`Edit`).

2. **Different event set** — `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, subagent events. Good for animation; different from Claude's `PreToolUse`+`Stop` only.

3. **Preview status** — behavior and schemas still moving; expect upstream churn.

4. **Desktop vs remote** — cloud agents run hooks in a sandbox with different event availability.

**Minimum events:** `PreToolUse`, `PostToolUse`, `Stop` (+ maybe `SessionStart` for idle/session boundaries).

**Reference:** [VS Code agent hooks (preview)](https://code.visualstudio.com/docs/copilot/customization/hooks)

---

### Antigravity 2.0 (IDE + CLI `agy`)

**Config:** JSON hooks at global + workspace level (May 2026); `AGENTS.md` for agent topology, not hook wiring.

**Why it's the haziest:**

1. **Very new** — hooks just landed in Antigravity 2.0 (May 19–22, 2026); schemas and file locations are less battle-tested than Cursor/VS Code.

2. **Three surfaces** — Antigravity IDE, Antigravity CLI (`agy`), Managed Agents API. Hook story may differ per surface (CLI vs IDE parity risk, same as Cursor).

3. **Likely Claude-adjacent** — uses `AGENTS.md`, `.agents/skills/`, multi-model routing. Probably closer to Claude Code hooks than Codex, but **don't assume** — capture fixtures first.

4. **SoA in Antigravity repos** — if users run SoA delivery inside Antigravity workspaces, need whatever env var Antigravity sets for project root (TBD; may be cwd-only initially).

**First step before any code:** run fixture capture for Antigravity and commit real stdin samples.

**Reference:** [Antigravity 2.0 announcement](https://antigravity.google/blog/introducing-google-antigravity-2-0)

---

## Work breakdown (honest sizing)

| Workstream | Effort | Notes |
| --- | --- | --- |
| **A. Hook installer per platform** | Small | Extend `installHooks()` — 4 config file formats |
| **B. Platform adapter layer** | Medium–Large | `normalizeHookInput(platform, rawJson) → HookInput` |
| **C. Tool-name mapping table** | Medium | Cursor `Shell`→bash heuristics; VS Code `editFiles`→implementing; etc. |
| **D. Event-name mapping** | Small–Medium | `preToolUse`→tool_use, `Stop`/`stop`→requesting_input, session_end semantics |
| **E. SoA project root resolution** | Small | `workspace_roots`, `cwd`, platform env vars |
| **F. Contract/schema updates** | Small | Add origins: `cursor`, `vscode`, `antigravity`; update docs |
| **G. Fixture capture + tests** | Medium | Real stdin per platform per event; classification tests |
| **H. XP/sync integration** | Large (optional) | Cursor/Antigravity/VS Code JSONL or telemetry — may not exist or may be undocumented |
| **I. CLI vs desktop matrix** | Ongoing | Document what works where; degrade gracefully |

**The instinct that this is "just hook config + inject codogotchi-hook" is half right.** Yes, you register the binary in each platform's hook config. **The other half** is building an adapter + mapping layer so the same classifier produces meaningful states instead of `idle` for every Cursor file edit.

---

## Suggested phasing

Do not bolt all four onto Phase 04 (SoA hook hardening). Sequence by **schema clarity × user share**:

| Phase | Scope |
| --- | --- |
| **Phase 04** (already planned) | SoA read-path hardening for Claude/Codex |
| **Phase 05a or 06** | **Cursor hooks** — dogfood Cursor; best fixture access; IDE-first, CLI caveats documented |
| **Next** | **VS Code Copilot hooks** — large audience; tool-name mapping is the main lift |
| **Next** | **Antigravity** — wait for stable hook docs + real fixtures from own usage |
| **Later** | XP/sync sources for new platforms (only if activity logs are accessible) |

Each platform phase is roughly **3 tickets**:

1. Capture fixtures + adapter + installer
2. Tool/event mapping + SoA root + tests
3. Docs + validation runbook row ("drive agent X through implementing / testing / stop")

---

## Ironman (why someone would disagree)

A smart person would say: _"Skip formal multi-platform support. Cursor and VS Code both speak hooks.json now. Write one thin wrapper script that maps stdin to `{origin,kind,name,command}` and call it a day. Don't extend the origin enum or build a phase."_

That works for **a personal shim**. It doesn't change the recommendation for **product-grade support** because: unmapped tool names mean the pet sits idle during real work; wrong origin breaks debugging and future sync; Cursor CLI gaps will look like codogotchi bugs; and you'd be maintaining regex-on-JSON without fixtures when upstream schemas drift weekly.

---

## Checklist

### Done today

- [x] Claude Code hooks (desktop + CLI)
- [x] Codex hooks (desktop + CLI)
- [x] Shared hook binary + `state.json` pipeline
- [x] SoA event override (when project dir resolves)
- [x] Renderer for all 15 states

### Not done

- [ ] Platform adapters for Cursor / VS Code / Antigravity
- [ ] Tool-name translation tables per platform
- [ ] SoA root from `workspace_roots` / platform env vars
- [ ] `codogotchi setup` installers for new platforms
- [ ] Fixture capture + tests per platform
- [ ] Contract origins + docs update
- [ ] XP/sync for non-Claude/Codex agents
- [ ] CLI-vs-desktop parity matrix documented

### Immediate next move

Capture real hook stdin from a Cursor session, inspect what `preToolUse` / `afterFileEdit` / `stop` actually look like, then decide whether a wrapper or a proper adapter layer is enough. One afternoon of fixtures saves a week of guessing.

---

## Architecture (current)

```
┌─────────────────────┐     ┌─────────────────────┐
│   Claude Code       │     │   Codex Desktop     │
│ PreToolUse, Stop    │     │ Pre/PostToolUse,    │
│                     │     │ SessionStart, Stop  │
└─────────┬───────────┘     └─────────┬───────────┘
          │ JSON stdin                │ JSON stdin + env prefix
          ▼                           ▼
    ┌─────────────────────────────────────────┐
    │  codogotchi-hook (Bun binary)           │
    │  packages/cli/bin/codogotchi-hook.ts   │
    │    → runHookFromStdin → classifyEvent   │
    │    → tail-read .soa/events.ndjson       │
    │    → write ~/.codogotchi/state.json     │
    └─────────────────────────────────────────┘
          │
          ▼
    ┌─────────────────────────────────────────┐
    │  Menubar app (LivePollingDriver)        │
    │  polls $CODOGOTCHI_HOME/state.json     │
    └─────────────────────────────────────────┘
```

**Target architecture** adds adapter boxes before `classifyEvent` for Cursor, VS Code, and Antigravity stdin dialects, plus extended SoA root resolution.
