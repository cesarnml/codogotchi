# Codogotchi platform extension and signal pipeline research

Date: 2026-05-27  
Status: Research draft (codebase scan + public platform docs)  
Related: [multi-platform-hook-support.md](./multi-platform-hook-support.md), [codogotchi-native-codex-pet-feature-parity-roadmap.md](./codogotchi-native-codex-pet-feature-parity-roadmap.md), [codex-native-pet-animation-triggers.md](./codex-native-pet-animation-triggers.md)

---

## Executive summary

Codogotchi today is a **hook-driven animation pipeline** for Claude Code and Codex only. The hook binary classifies each lifecycle event into a closed `ActivityState`, writes `~/.codogotchi/state.json`, and the macOS menubar app polls that file at 1 Hz. SoA delivery gates are **indirect**: Son-of-Anton appends to per-repo `.soa/events.ndjson`, and the hook **tails that file on the next hook invocation** to override heuristics.

Three gaps dominate real usage (confirmed 2026-05-27 on Cursor-only workflows):

1. **Platform mis-attribution** — Cursor hook traffic is labeled `source_origin: "claude_code"` because origin detection is a two-line heuristic, not platform truth.
2. **Stale attention states** — `requesting_input` (Codex `waving` row) can persist indefinitely after a turn completes because there is no TTL / session-boundary decay (unlike native Codex’s notification + expiry model).
3. **Shallow tool logging** — transition log records `source_name: "Bash"` but not the shell command string; generic Bash (`ls`, `rg`) maps to `idle` even when the agent is clearly “working.”

**Recommendation:** Treat the next major increment as two coupled tracks:

| Track | What | Why first |
| --- | --- | --- |
| **A. Signal honesty** | Platform adapters + truthful `source_origin` + richer `tool_use` payload in logs | Unblocks Cursor/VS Code/Antigravity and fixes debugging |
| **B. Attention UX** | Notification-tray semantics + TTL decay to `idle` | Fixes “stuck waving” (highest user-visible pain) |
| **C. Work-mode taxonomy** | Optional `work_mode: thinking \| implementing \| testing` parallel to `activity_state` | Better animation + log semantics without replacing SoA gates |
| **D. SoA direct write** | SoA emits to `~/.codogotchi/` when enabled, not only repo `.soa/events.ndjson` | Removes hook-coupling and missed gates when hooks are quiet |

Antigravity 2.0 (released ~May 19–22, 2026) is **researchable but fixture-poor** — capture real stdin before betting the adapter shape. Cursor and VS Code Copilot hooks are **documented and shippable** with an adapter layer.

---

## 1. How Codogotchi drives animation today (codebase)

### 1.1 End-to-end flow

```
Agent platform (Claude / Codex)
  → spawns codogotchi-hook on lifecycle events
  → classifyEvent(HookInput) + optional SoA tail merge
  → atomic write ~/.codogotchi/state.json
  → LivePollingDriver (1 Hz) reads state.json
  → MenubarRenderer / FloatingPetScene maps ActivityState → sprite rows
  → TransitionLog (menubar only) appends NDJSON on state *changes*
```

Key files:

| Component | Path |
| --- | --- |
| Hook entry | `packages/cli/bin/codogotchi-hook.ts` |
| Classify + SoA merge + state write | `packages/cli/src/hook-binary.ts` |
| Hook installer | `packages/cli/src/hooks.ts` |
| SoA tail reader | `packages/engine/src/sources/soa.ts` |
| Polling | `apps/menubar/Sources/LivePollingDriver.swift` |
| Transition log | `apps/menubar/Sources/TransitionLog.swift` |
| Contracts | `packages/contracts/src/animation-state.ts`, `state-json.ts`, `soa-events.ts` |

### 1.2 Hook installation (today)

**Claude Code** (`~/.claude/settings.json`):

- Events: `PreToolUse`, `Stop`
- Command: bare `codogotchi-hook` (relies on Claude setting `CLAUDE_PROJECT_DIR`)

**Codex** (`~/.codex/hooks.json`):

- Events: `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`
- Command: `CODOGOTCHI_HOME=… CODOGOTCHI_CONVEX_URL=… codogotchi-hook`
- Enables `hooks = true` in `~/.codex/config.toml`

No installer paths yet for Cursor, VS Code, or Antigravity.

### 1.3 Classification rules (`classifyEvent`)

**Precedence inside one hook invocation:**

1. If stdin is explicit SoA gate (`origin: soa`, `kind: gate`) → map via `SOA_GATE_TO_STATE`
2. Else if `hook_event_name === "stop"` (case-insensitive) → `requesting_input` or `errored`
3. Else if `is_error` → `errored`
4. Else if `kind === "tool_use"`:
   - `Edit` / `Write` / `MultiEdit` → `implementing`
   - `Bash` + test-runner prefix → `running-tests`
   - `Bash` + `git push` prefix → `pushing`
   - `Bash` otherwise → **`idle`** (important gap)
   - `Read` ×3 consecutive (persisted in `~/.hook-counters.json`) → `reviewing`
5. Default → `idle`

**SoA override (same invocation):** After classification, `runHook` tails `${projectRoot}/.soa/events.ndjson` since last offset; **latest mapped gate wins** for `activity_state` and replaces `source_event` with `{ origin: "soa", kind: "gate", name }`.

### 1.4 Origin detection (why Cursor looks like Claude)

```typescript
// packages/cli/src/hook-binary.ts (conceptual)
function rawHookOrigin(input) {
  if (input.origin !== undefined) return input.origin;
  if (input.hook_event_name && input.hook_event_name === input.hook_event_name.toLowerCase())
    return "codex";
  return "claude_code";  // ← everything else, including Cursor
}
```

Cursor sends **camelCase** event names (`preToolUse`, `postToolUse`, `stop`, `beforeShellExecution`). Those are not all-lowercase, so origin becomes `claude_code`. Tool names also differ (`Shell` vs `Bash`, `afterFileEdit` vs `Write`).

**Evidence (2026-05-27):** `state-transitions.log` shows `source_origin: "claude_code"` with `source_name` in `Bash`, `Glob`, `Shell`, `Read`, `Grep`, `MCP:…` while the user only ran Cursor — consistent with this heuristic, not with ground truth.

### 1.5 What gets logged where

| Sink | Written by | Fields today | Gap |
| --- | --- | --- | --- |
| `state.json` | Hook | `activity_state`, `source_event.{origin,kind,name}`, `hp`, `updated_at` | No command string; no work mode |
| `state-transitions.log` | Menubar (`TransitionLog`) | `state`, `prev`, `source_*`, heartbeat | **No `command`**; origin wrong for Cursor |
| `.soa/events.ndjson` | SoA (`appendSoaEvent`) | `name`, `ts`, `plan_key`, `ticket_id`, optional `payload` | Per-repo; hook must run to consume |

The hook **uses** `command` for Bash heuristics but **does not persist** it to `state.json` or the transition log.

### 1.6 Animation mapping (not the same as “work mode”)

`ActivityState` is a **15-value closed enum** (`idle`, `implementing`, `running-tests`, `reviewing`, `pushing`, SoA gates, `requesting_input`, `errored`, …). Sprites map via:

- Codex sheet rows for: `idle`, `implementing`, `running-tests`, `waiting`, `requesting_input`, `errored`
- Codogotchi sheet rows for: SoA-only states + `reviewing`, `pushing`

There is **no** first-class `thinking | implementing | testing` dimension today.

---

## 2. Platform extension research (web + docs)

### 2.1 Cursor (you are here)

**Docs:** [Cursor Hooks](https://cursor.com/docs/agent/hooks) (Agent + Tab + app lifecycle).

**Model:** JSON stdin/stdout per hook command; config at `~/.cursor/hooks.json` or `.cursor/hooks.json`.

**Relevant agent events (superset of Claude):**

| Cursor event | Codogotchi use |
| --- | --- |
| `preToolUse` / `postToolUse` | Generic tool boundary (all tools) |
| `beforeShellExecution` / `afterShellExecution` | Bash-like commands (`tool_name` often `Shell`) |
| `beforeReadFile` / `afterFileEdit` | Read vs write paths (file edits are not `Edit`/`Write`) |
| `beforeMCPExecution` / `afterMCPExecution` | MCP (e.g. Context7, browser) → **Thinking** heuristics |
| `stop` / `sessionEnd` | Turn complete → clear `requesting_input`, TTL |
| `sessionStart` | Session boundary → reset counters / idle |

**Project root:** `workspace_roots[]` in payload — must feed `resolveSoaRoot()` (today only `CLAUDE_PROJECT_DIR`, `CODEX_PROJECT_DIR`, `cwd`).

**CLI caveat:** Cursor CLI may fire a **subset** of IDE hooks; document parity matrix (IDE vs CLI).

**Installer target:** extend `packages/cli/src/hooks.ts` with `~/.cursor/hooks.json` registration calling:

```bash
CODOGOTCHI_HOME=… CURSOR_PROJECT_DIR=<first-workspace-root> codogotchi-hook --platform cursor
```

(Exact env injection TBD; may require wrapper script.)

### 2.2 VS Code + GitHub Copilot Agent (Preview)

**Docs:** [Agent hooks in VS Code](https://code.visualstudio.com/docs/copilot/customization/hooks) (Preview).

**Model:** Same family as Copilot CLI — JSON over stdio; configs at `.github/hooks/*.json`, `~/.copilot/hooks/`, or Claude-compatible `.claude/settings.json`.

**Events:** `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`.

**Critical platform note:** VS Code explicitly warns that **tool names differ** from Claude (`create_file`, `replace_string_in_file`, etc. vs `Write`/`Edit`). Requires a **tool alias table**, not copy-paste of Claude heuristics.

**Origin enum extension:** add `vscode` or `copilot` to `sourceEventOriginSchema` in `packages/contracts/src/state-json.ts`.

### 2.3 Google Antigravity 2.0 (~May 19–22, 2026)

**Surfaces:** Desktop IDE, CLI (`agy`), SDK, Managed Agents API — shared “agent harness.”

**Hooks (reported / secondary sources):**

- JSON hook config at global + workspace level (exact paths less battle-tested than Cursor/VS Code).
- SDK exposes **policy hooks** (`deny` / `allow` / `ask_user`) on tools — different shape from stdin lifecycle hooks.
- CLI inherits Gemini CLI hook concepts (Skills, Hooks, Subagents) per Google’s migration messaging; Gemini CLI sunsets **June 18, 2026**.

**Risk:** newest platform, highest schema churn. **Do not implement without captured fixtures** from a real Antigravity session.

**First step:** Run `scripts/capture-hook-fixtures.sh` pattern adapted for Antigravity; commit stdin samples under `packages/engine/test/fixtures/hooks/antigravity/`.

### 2.4 Platform comparison table

| Platform | Hook config | Event casing | Shell tool name | File write events | Maturity for Codogotchi |
| --- | --- | --- | --- | --- | --- |
| Claude Code | `settings.json` | PascalCase | `Bash` | `Edit`/`Write` via PreToolUse | **Shipped** |
| Codex | `hooks.json` | snake_case | `Bash` | Same | **Shipped** |
| Cursor | `hooks.json` | camelCase | `Shell` | `afterFileEdit`, etc. | **High value, adapter needed** |
| VS Code Copilot | `hooks` + plugins | PascalCase (often) | varies | VS Code-specific names | **High audience, mapping table** |
| Antigravity 2.0 | JSON (TBD) | TBD | TBD | TBD | **Wait for fixtures** |

---

## 3. Richer `tool_use` logging and work-mode taxonomy

### 3.1 User-facing goal

When the agent uses **Bash**, logs and UI should answer:

- What command ran? (`rg`, `pytest`, `bun run verify`, …)
- What *kind* of work was that?
  - **Thinking** — read/search/explore (files, structure, docs, web, MCP doc fetch)
  - **Implementing** — create/change code or config
  - **Testing** — run or author tests, fix failures

If heuristics are uncertain → **fallback to Implementing** (animation: keep current `implementing` / laptop row).

### 3.2 Proposed `work_mode` (parallel field, non-breaking)

Add optional fields (names tentative):

```json
{
  "activity_state": "implementing",
  "work_mode": "thinking",
  "tool": {
    "name": "Bash",
    "command": "rg -n classifyEvent packages/cli/src/hook-binary.ts"
  },
  "platform": "cursor",
  "attention": {
    "summary": "Waiting for your reply",
    "reason_kind": "waiting_on_user_input",
    "expires_at": "2026-05-27T10:00:00.000Z"
  }
}
```

- **`activity_state`** — unchanged contract for renderer + SoA gates.
- **`work_mode`** — drives subtler UI (badge, tray text, future sprite row) without collapsing SoA semantics.
- **`tool.command`** — persisted for Bash/Shell always; optional for other tools.

### 3.3 Heuristic mapping (starting point)

Classify `(tool_name, command, hook_event)` → `work_mode`:

| Signals | work_mode | Maps to current ActivityState (default) |
| --- | --- | --- |
| `Read`, `Glob`, `Grep`, `rg`/`grep`/`find`, MCP doc/search, `WebSearch` | **thinking** | `reviewing` after 3× Read else `idle` |
| `Edit`, `Write`, `MultiEdit`, `afterFileEdit`, VS Code `replace_string_in_file` / `create_file` | **implementing** | `implementing` |
| Bash matching test runners (`pytest`, `vitest`, `bun test`, …) | **testing** | `running-tests` |
| Bash `git push` | **implementing** (or keep `pushing`) | `pushing` |
| Bash unknown | **implementing** (fallback) | today → `idle` (**change recommended**) |
| MCP move_agent / IDE-only | **thinking** or ignore | platform-specific |

**Implementation locus:** new module e.g. `packages/cli/src/work-mode.ts` called from `classifyEvent` after normalization; unit tests per platform fixtures.

### 3.4 Transition log improvements

Extend `TransitionLog` line shape:

```json
{
  "ts": "...",
  "state": "requesting_input",
  "prev": "implementing",
  "schema_version": 2,
  "source_origin": "cursor",
  "source_kind": "tool_use",
  "source_name": "Shell",
  "tool_command": "rg -n rawHookOrigin",
  "work_mode": "thinking",
  "platform": "cursor"
}
```

This makes log search (`rg Bash`, `rg pytest`) honest and debuggable.

---

## 4. Why `requesting_input` / waving sticks (and how native Codex differs)

**Codogotchi today:**

- `Stop` hook → `requesting_input` (unless error/max_tokens).
- No automatic return to `idle` when the user walks away after the agent finished.
- Menubar polls `state.json` faithfully; **staleness is a product-policy gap**, not a read failure.

**Native Codex:**

- Session status machine + notification queue + **TTL** (e.g. running 3 min, waiting 24h, review 7d).
- Pet pose decays even if `activity_state` in a local file would still say “waiting.”

**Align with:** [codogotchi-native-codex-pet-feature-parity-roadmap.md](./codogotchi-native-codex-pet-feature-parity-roadmap.md) — notification tray + `attention.expires_at` + renderer shows `idle` when expired.

**Additional hook triggers for Cursor:**

- Map `stop` / `sessionEnd` → end-of-turn: write `idle` or schedule short TTL.
- Map `sessionStart` → reset `read_run`, clear attention.

---

## 5. SoA gate events: rethink the pipeline

### 5.1 Today (indirect, hook-coupled)

```
SoA deliver command
  → appendSoaEvent(projectRoot, event)
  → <repo>/.soa/events.ndjson

(later, when agent happens to fire a hook)
  → hook runHook tails .soa/events.ndjson
  → maybe override activity_state
  → write state.json
```

**Problems:**

| Issue | Effect |
| --- | --- |
| Gate only visible on **next hook** | If user stops using Claude/Codex hooks, SoA gates never reach the pet |
| **Wrong project root** | Cursor not in `resolveSoaRoot`; cwd may be wrong in multi-root workspaces |
| **Two writers, one consumer** | Debugging requires correlating repo file + hook counters + state.json |
| SoA events not in transition log unless hook runs | Menubar log may show `implementing` while gate fired minutes ago |

SoA writer today (`appendSoaEvent` in `.son-of-anton/tools/delivery/soa-event-feed.ts`):

- Respects `config.codogotchi?.enabled === false` → skip write.
- Always writes under **`projectRoot/.soa/events.ndjson`**, never `~/.codogotchi/`.

### 5.2 Proposed: SoA writes directly to Codogotchi home

When `codogotchi.enabled !== false` in consumer repo’s `orchestrator.config.json`:

```
SoA deliver command
  → appendCodogotchiGateEvent(home, event)   // NEW
  → ~/.codogotchi/gate-events.ndjson (or single state.json patch)

Renderer / hook
  → read latest gate from ~/.codogotchi (not repo tail)
  → merge with platform hook classification
```

**Options (pick one in design):**

| Option | Pros | Cons |
| --- | --- | --- |
| **A. `~/.codogotchi/gate-events.ndjson`** | Same tail semantics as today; multi-repo | Another file |
| **B. Patch `state.json` in place** | Single poll target | Race: hook vs SoA writers need lock (already have `.hook.lock`) |
| **C. Both** | SoA append gate file + hook merges on run | Slightly redundant |

**Recommended:** **A + hook merge** for v1 (minimal menubar change); optional **B** later for atomic “single source of truth.”

**SoA-side changes (son-of-anton consumer):**

- New helper: `appendCodogotchiEvent(config, event)` → `~/.codogotchi/gate-events.ndjson`
- Gate on `config.codogotchi?.enabled === false` (same as today)
- Still **optional** emit to `.soa/events.ndjson` for backward compat / debugging until deprecated

**Codogotchi-side changes:**

- `readGateEventsSince(home, tail)` mirroring `readSoaEventsSince`
- `runHook` merges latest gate from **home file first**, then optional repo tail fallback during migration
- `TransitionLog.recordTransition` includes gate name when `source_kind === "gate"`

**Config discovery:** SoA already reads `orchestrator.config.json` in the consumer repo for `codogotchi.enabled`. Home path from `CODOGOTCHI_HOME` env (already set for Codex hooks).

### 5.3 Precedence after redesign

1. Latest **global** gate event (SoA → `~/.codogotchi/`) if fresh
2. Latest **repo** gate event (legacy `.soa/events.ndjson`) during migration
3. Platform hook classification
4. Default `idle`

Freshness window: same as today — gate seen since last hook offset, or TTL on gate age (align with attention TTL).

---

## 6. Suggested phased roadmap

### Phase 1 — Signal honesty (Cursor first)

- Platform adapter layer: `normalizeHookInput(platform, raw) → HookInput`
- Fix `rawHookOrigin` — never infer; set from installer/platform flag
- Extend `sourceEventOriginSchema`: `cursor`, `vscode`, `antigravity`, `copilot`
- Cursor `hooks.json` installer + fixture capture
- Persist `tool.command` on Bash/Shell in classify path + transition log
- Change Bash unknown fallback: `idle` → **`implementing`** (or `work_mode: implementing`)

### Phase 2 — Attention tray + TTL (highest UX value)

See parity roadmap. Unblocks stuck `requesting_input` without waiting for full platform parity.

### Phase 3 — `work_mode` taxonomy

- Implement thinking / implementing / testing heuristics
- Optional menubar badge or tray line driven by `work_mode`
- Future: map work_mode to animation rows (if product wants distinct sprites)

### Phase 4 — VS Code Copilot hooks

- Tool alias table for Copilot-specific tool names
- Installer for `.github/hooks` or `~/.copilot/hooks`

### Phase 5 — SoA direct write

- `appendCodogotchiGateEvent` in SoA
- Hook reads `~/.codogotchi/gate-events.ndjson`
- Deprecation path for repo-only tail

### Phase 6 — Antigravity

- Fixture capture from real sessions
- Adapter + installer once schema stable

---

## 7. Ironman (strongest counter-argument)

**“Don’t expand platforms or SoA wiring — fix Cursor mislabeling with a one-line origin override and move on.”**

A smart engineer would argue the product should stay a thin **state.json** shim, not become a mini-Codex notification system. Every new platform adapter is ongoing tax when hook schemas change weekly.

**Why that doesn’t change the recommendation:** You already feel pain on Cursor-only workflows *today* — wrong origin, stuck waving, Bash-heavy logs that don’t explain commands. That’s not “optional platform support”; it’s **incorrect telemetry** while using the primary IDE. Minimum bar: truthful `platform` field + TTL + Bash command in logs. Full tray parity can follow, but signal honesty and decay are not optional.

---

## 8. Immediate next actions (concrete)

1. **Capture Cursor fixtures** — `preToolUse` (Shell), `afterFileEdit`, `stop`, `beforeMCPExecution` → commit under `packages/engine/test/fixtures/hooks/cursor/`.
2. **Reproduce origin bug** — add test: stdin with `hook_event_name: "preToolUse"` must **not** classify as `codex` or default `claude_code` without adapter.
3. **Prototype `work_mode` classifier** — table-driven tests for Bash commands (`rg` → thinking, `pytest` → testing).
4. **Design `~/.codogotchi/gate-events.ndjson`** — contract doc + SoA stub in alignment draft.
5. **Ship attention TTL** in renderer (can precede full tray UI) — stops long-lived `requesting_input` in menubar.

---

## 9. Open questions

| Question | Notes |
| --- | --- |
| Should `work_mode` change sprites or only tray/tooltip? | Sprites need art + row map; tray is faster |
| Single global gate log vs per-repo gates? | User proposal favors global `~/.codogotchi/` |
| Does Cursor CLI get full hooks? | Document degradation; don’t promise parity |
| Antigravity hook stdin shape? | Block implementation until fixtures exist |
| XP/sync for Cursor/Antigravity JSONL? | Separate large track; hooks-only still valuable |

---

## 10. References

- Code: `packages/cli/src/hook-binary.ts`, `hooks.ts`, `packages/engine/src/sources/soa.ts`
- Contracts: `docs/contracts/animation-state-vocabulary.md`, `docs/contracts/soa-event-feed.md`
- Prior notes: `notes/public/multi-platform-hook-support.md`
- Cursor hooks: https://cursor.com/docs/agent/hooks
- VS Code Copilot hooks: https://code.visualstudio.com/docs/copilot/customization/hooks
- Antigravity SDK (policies/hooks): https://github.com/google-antigravity/antigravity-sdk-python
