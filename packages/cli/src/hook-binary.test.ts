import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  type ProfileResponse,
  parseStateJson,
  STATE_JSON_SCHEMA_VERSION,
  type StateJsonV1,
} from "@codogotchi/contracts";
import { classifyEvent, type HookInput, runHook } from "./hook-binary";

const FIXED_NOW = new Date("2026-05-18T15:00:00.000Z");

function readState(home: string): StateJsonV1 {
  const raw = readFileSync(join(home, "state.json"), "utf8");
  return parseStateJson(JSON.parse(raw));
}

describe("classifyEvent", () => {
  it("classifies Claude Code Edit tool-use as implementing", () => {
    const out = classifyEvent(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Edit",
      },
      { readRun: 0 },
    );
    expect(out.state).toBe("implementing");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.kind).toBe("tool_use");
    expect(out.sourceEvent.name).toBe("Edit");
    expect(out.readRun).toBe(0);
  });

  it("classifies Write tool-use as implementing", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "tool_use", name: "Write" },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies MultiEdit tool-use as implementing", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "tool_use", name: "MultiEdit" },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies Bash 'bun test' as testing", () => {
    const out = classifyEvent(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Bash",
        command: "bun test packages/engine",
      },
      { readRun: 0 },
    );
    expect(out.state).toBe("testing");
  });

  it("classifies Bash 'pytest' as testing", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "pytest -k smoke",
        },
        { readRun: 0 },
      ).state,
    ).toBe("testing");
  });

  it("classifies Bash 'git push' as implementing (git push)", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "git push origin main",
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies Bash 'grep' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: 'grep "foo" bar.ts',
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'find' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: 'find . -name "*.ts"',
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'rg' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "rg pattern",
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'ls' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "ls -la",
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'cat' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "cat README.md",
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'jq' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "jq '.foo' file.json",
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'npm install' as implementing", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "npm install",
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies Bash 'bun run build' as implementing", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "bun run build",
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies Bash 'echo hello' as implementing", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "echo hello",
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies Bash with undefined command as implementing", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: undefined,
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies Cursor Shell 'grep' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Shell",
          command: 'grep "foo" bar.ts',
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Cursor Shell 'npm install' as implementing", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Shell",
          command: "npm install",
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("classifies Cursor Shell with undefined command as implementing", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Shell",
          command: undefined,
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("does not false-positive 'catfish' as thinking — word-boundary guard", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "catfish data.txt",
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("does not false-positive 'lsblk' as thinking — word-boundary guard", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "lsblk",
        },
        { readRun: 0 },
      ).state,
    ).toBe("implementing");
  });

  it("thinking bucket resets readRun to 0", () => {
    const out = classifyEvent(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Bash",
        command: "grep pattern src/",
      },
      { readRun: 2 },
    );
    expect(out.state).toBe("thinking");
    expect(out.readRun).toBe(0);
  });

  it("requires 3 consecutive Read tool-uses to classify as thinking (Read streak)", () => {
    const first = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: 0 },
    );
    expect(first.state).toBe("idle");
    expect(first.readRun).toBe(1);

    const second = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: first.readRun },
    );
    expect(second.state).toBe("idle");
    expect(second.readRun).toBe(2);

    const third = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: second.readRun },
    );
    expect(third.state).toBe("thinking");
    expect(third.readRun).toBe(3);
  });

  it("resets Read run when an Edit interrupts", () => {
    const after_edit = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { readRun: 2 },
    );
    expect(after_edit.state).toBe("implementing");
    expect(after_edit.readRun).toBe(0);
  });

  it("classifies SoA ticket_started as ticket_started", () => {
    expect(
      classifyEvent(
        { origin: "soa", kind: "gate", name: "ticket_started" },
        { readRun: 0 },
      ).state,
    ).toBe("ticket_started");
  });

  it("classifies SoA verification_failed as errored", () => {
    expect(
      classifyEvent(
        { origin: "soa", kind: "gate", name: "verification_failed" },
        { readRun: 0 },
      ).state,
    ).toBe("errored");
  });

  it("classifies SoA ticket_completed as ticket_completed", () => {
    expect(
      classifyEvent(
        { origin: "soa", kind: "gate", name: "ticket_completed" },
        { readRun: 0 },
      ).state,
    ).toBe("ticket_completed");
  });

  it("classifies SoA review_clean_recorded as review_clean", () => {
    expect(
      classifyEvent(
        { origin: "soa", kind: "gate", name: "review_clean_recorded" },
        { readRun: 0 },
      ).state,
    ).toBe("review_clean");
  });

  it("classifies session_start with no prior activity as idle", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "session_start", name: "start" },
        { readRun: 0 },
      ).state,
    ).toBe("idle");
  });

  it("classifies session_end as idle", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "session_end", name: "end" },
        { readRun: 0 },
      ).state,
    ).toBe("idle");
  });

  it("classifies Claude Code raw stdin {tool_name:'Edit'} as implementing", () => {
    const out = classifyEvent(
      { tool_name: "Edit", hook_event_name: "PreToolUse" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("implementing");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.kind).toBe("tool_use");
    expect(out.sourceEvent.name).toBe("Edit");
  });

  it("classifies Codex raw stdin as codex-origin tool-use", () => {
    const out = classifyEvent(
      { tool_name: "Edit", hook_event_name: "pre_tool_use" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("implementing");
    expect(out.sourceEvent.origin).toBe("codex");
    expect(out.sourceEvent.kind).toBe("tool_use");
    expect(out.sourceEvent.name).toBe("Edit");
  });

  it("classifies Codex session_end raw stdin as session_end", () => {
    const out = classifyEvent({ hook_event_name: "session_end" } as HookInput, {
      readRun: 0,
    });
    expect(out.state).toBe("idle");
    expect(out.sourceEvent.origin).toBe("codex");
    expect(out.sourceEvent.kind).toBe("session_end");
  });

  it("classifies Stop event as standby", () => {
    const out = classifyEvent({ hook_event_name: "Stop" } as HookInput, {
      readRun: 0,
    });
    expect(out.state).toBe("standby");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.kind).toBe("session_end");
  });

  it("classifies Stop event with stop_reason max_tokens as errored", () => {
    const out = classifyEvent(
      { hook_event_name: "Stop", stop_reason: "max_tokens" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("errored");
  });

  it("classifies explicit is_error payload as errored", () => {
    const out = classifyEvent(
      { hook_event_name: "Stop", is_error: true } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("errored");
  });

  it("regression: Edit tool-use still classifies as implementing (v2 path)", () => {
    const out = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Edit" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("implementing");
  });

  // P6.05: Cursor origin fix + shell hooks
  it("Cursor afterFileEdit classifies as implementing with cursor origin", () => {
    const out = classifyEvent(
      { hook_event_name: "afterFileEdit" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("implementing");
    expect(out.sourceEvent.origin).toBe("cursor");
  });

  it("Cursor beforeShellExecution 'grep' classifies as thinking with cursor origin", () => {
    const out = classifyEvent(
      {
        hook_event_name: "beforeShellExecution",
        command: "grep foo",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("thinking");
    expect(out.sourceEvent.origin).toBe("cursor");
  });

  it("Cursor afterShellExecution 'npm install' classifies as implementing with cursor origin", () => {
    const out = classifyEvent(
      {
        hook_event_name: "afterShellExecution",
        command: "npm install",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("implementing");
    expect(out.sourceEvent.origin).toBe("cursor");
  });

  it("Cursor lowercase 'stop' has cursor origin (not claude_code)", () => {
    const out = classifyEvent({ hook_event_name: "stop" } as HookInput, {
      readRun: 0,
    });
    expect(out.sourceEvent.origin).toBe("cursor");
  });

  it("Claude Code PascalCase 'Stop' has claude_code origin", () => {
    const out = classifyEvent({ hook_event_name: "Stop" } as HookInput, {
      readRun: 0,
    });
    expect(out.sourceEvent.origin).toBe("claude_code");
  });
});

describe("runHook", () => {
  let home: string;
  let originalClaudeProjectDir: string | undefined;
  let originalCodexProjectDir: string | undefined;

  beforeEach(async () => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-hook-"));
    await mkdir(home, { recursive: true });
    // Isolate runHook's SoA-root resolution from the invoking process's real
    // working directory. resolveSoaRoot() consults CLAUDE_PROJECT_DIR /
    // CODEX_PROJECT_DIR / CWD; without redirection, a worktree that contains
    // a real `.soa/events.ndjson` (e.g. when these tests run inside a
    // delivery orchestrator worktree) reclassifies the activity state from
    // whatever the test injected to whatever the last real SoA gate event
    // was. Point CLAUDE_PROJECT_DIR at the fresh tmpdir so SoA root resolves
    // to an empty location for the duration of the test.
    originalClaudeProjectDir = process.env.CLAUDE_PROJECT_DIR;
    originalCodexProjectDir = process.env.CODEX_PROJECT_DIR;
    process.env.CLAUDE_PROJECT_DIR = home;
    delete process.env.CODEX_PROJECT_DIR;
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
    if (originalClaudeProjectDir === undefined) {
      delete process.env.CLAUDE_PROJECT_DIR;
    } else {
      process.env.CLAUDE_PROJECT_DIR = originalClaudeProjectDir;
    }
    if (originalCodexProjectDir !== undefined) {
      process.env.CODEX_PROJECT_DIR = originalCodexProjectDir;
    }
  });

  it("writes state.json on first event with default thriving overlay when no profile", async () => {
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.schema_version).toBe(STATE_JSON_SCHEMA_VERSION);
    expect(state.activity_state).toBe("implementing");
    expect(state.hp).toBe(100);
    expect(state.hp_overlay).toBe("thriving");
    expect(state.updated_at).toBe(FIXED_NOW.toISOString());
    expect(state.source_event.name).toBe("Edit");
  });

  it("layers HP from profile.json when present", async () => {
    const profile: Pick<ProfileResponse, "hp" | "mood"> & {
      [k: string]: unknown;
    } = {
      hp: 20,
      mood: "near_death",
      profile_id: "p",
      handle: "h",
      xp_by_source: {
        claude_code: 0,
        codex: 0,
        github: 0,
        wakatime: 0,
      },
      total_xp: 0,
      stage: 1,
      died_at: null,
      cause: null,
      death_count: 0,
      last_signal_at_by_source: {
        claude_code: null,
        codex: null,
        github: null,
        wakatime: null,
      },
      updated_at: 0,
    };
    writeFileSync(join(home, "profile.json"), JSON.stringify(profile), "utf8");

    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.hp).toBe(20);
    expect(state.hp_overlay).toBe("near_death");
  });

  it("classifies SoA gate event as ticket_completed", async () => {
    await runHook(
      { origin: "soa", kind: "gate", name: "ticket_completed" },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("ticket_completed");
  });

  it("tracks consecutive Read runs across invocations and switches to thinking", async () => {
    const input: HookInput = {
      origin: "claude_code",
      kind: "tool_use",
      name: "Read",
    };
    await runHook(input, { home, now: FIXED_NOW });
    await runHook(input, { home, now: FIXED_NOW });
    expect(readState(home).activity_state).toBe("idle");

    await runHook(input, { home, now: FIXED_NOW });
    expect(readState(home).activity_state).toBe("thinking");
  });

  it("serializes concurrent Read runs before updating counters", async () => {
    const input: HookInput = {
      origin: "claude_code",
      kind: "tool_use",
      name: "Read",
    };

    await Promise.all([
      runHook(input, { home, now: FIXED_NOW }),
      runHook(input, { home, now: FIXED_NOW }),
      runHook(input, { home, now: FIXED_NOW }),
    ]);

    expect(readState(home).activity_state).toBe("thinking");
  });

  it("resets Read run when an Edit interrupts across invocations", async () => {
    const read: HookInput = {
      origin: "claude_code",
      kind: "tool_use",
      name: "Read",
    };
    await runHook(read, { home, now: FIXED_NOW });
    await runHook(read, { home, now: FIXED_NOW });
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    await runHook(read, { home, now: FIXED_NOW });
    // One Read after reset is not enough for thinking.
    expect(readState(home).activity_state).toBe("idle");
  });

  it("writes STATE_JSON_SCHEMA_VERSION for a Stop event", async () => {
    await runHook({ hook_event_name: "Stop" } as HookInput, {
      home,
      now: FIXED_NOW,
    });
    const state = readState(home);
    expect(state.schema_version).toBe(STATE_JSON_SCHEMA_VERSION);
    expect(state.schema_version).toBe(4);
    expect(state.activity_state).toBe("standby");
  });

  it("classifies Stop event as standby in runHook", async () => {
    await runHook({ hook_event_name: "Stop" } as HookInput, {
      home,
      now: FIXED_NOW,
    });
    expect(readState(home).activity_state).toBe("standby");
  });

  it("classifies Stop+max_tokens as errored in runHook", async () => {
    await runHook(
      { hook_event_name: "Stop", stop_reason: "max_tokens" } as HookInput,
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("errored");
  });

  it("silently skips on malformed JSON without throwing", async () => {
    // Simulate a parser error path by passing invalid input through the
    // raw stdin entrypoint helper.
    const { runHookFromStdin } = await import("./hook-binary");
    await runHookFromStdin("{not valid json", { home, now: FIXED_NOW });
    // No state.json should have been written.
    expect(existsSync(join(home, "state.json"))).toBe(false);
  });

  it("writes atomically (no half-written file visible at target)", async () => {
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    // Sanity: target file is fully parseable.
    const raw = readFileSync(join(home, "state.json"), "utf8");
    expect(() => JSON.parse(raw)).not.toThrow();
  });

  // P6.04: attention payload tests
  it("Stop event writes attention with reason_kind input_requested and 2h expiry", async () => {
    await runHook({ hook_event_name: "Stop" } as HookInput, {
      home,
      now: FIXED_NOW,
    });
    const state = readState(home);
    expect(state.activity_state).toBe("standby");
    expect(state.attention).toBeDefined();
    expect(state.attention?.reason_kind).toBe("input_requested");
    expect(state.attention?.summary).toBe("Waiting for your input");
    expect(state.attention?.created_at).toBe(FIXED_NOW.toISOString());
    const expectedExpiry = new Date(
      FIXED_NOW.getTime() + 2 * 60 * 60 * 1000,
    ).toISOString();
    expect(state.attention?.expires_at).toBe(expectedExpiry);
  });

  it("Stop event with is_error:true writes attention with reason_kind error_blocked and 30m expiry", async () => {
    await runHook({ hook_event_name: "Stop", is_error: true } as HookInput, {
      home,
      now: FIXED_NOW,
    });
    const state = readState(home);
    expect(state.activity_state).toBe("errored");
    expect(state.attention).toBeDefined();
    expect(state.attention?.reason_kind).toBe("error_blocked");
    expect(state.attention?.summary).toBe(
      "Something went wrong — agent stopped",
    );
    expect(state.attention?.created_at).toBe(FIXED_NOW.toISOString());
    const expectedExpiry = new Date(
      FIXED_NOW.getTime() + 30 * 60 * 1000,
    ).toISOString();
    expect(state.attention?.expires_at).toBe(expectedExpiry);
  });

  it("Edit tool_use event writes no attention field", async () => {
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.attention).toBeUndefined();
  });

  it("Bash tool_use writes tool_command", async () => {
    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Bash",
        command: "grep foo",
      },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.tool_command).toBe("grep foo");
  });

  it("Shell tool_use writes tool_command", async () => {
    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Shell",
        command: "ls -la",
      },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.tool_command).toBe("ls -la");
  });

  it("Codex raw-stdin Bash event writes tool_command from tool_input.command", async () => {
    await runHook(
      {
        tool_name: "Bash",
        hook_event_name: "pre_tool_use",
        tool_input: { command: "echo hello" },
      } as HookInput,
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.tool_command).toBe("echo hello");
  });

  it("Edit tool_use writes no tool_command field", async () => {
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.tool_command).toBeUndefined();
  });

  it("gate state persists through subsequent tool_use events until cleared", async () => {
    // 1. ticket_started gate fires → state shows ticket_started
    await runHook(
      { origin: "soa", kind: "gate", name: "ticket_started" },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("ticket_started");

    // 2. Bash tool_use (heuristic idle) → state still shows ticket_started (sticky)
    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Bash",
        command: "ls -la",
      },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("ticket_started");

    // 3. Stop event → state shows standby (gate cleared)
    await runHook({ hook_event_name: "Stop" } as HookInput, {
      home,
      now: FIXED_NOW,
    });
    expect(readState(home).activity_state).toBe("standby");
  });

  it("a new gate event overwrites the sticky gate state", async () => {
    // First gate: ticket_started → ticket_started (sticky)
    await runHook(
      { origin: "soa", kind: "gate", name: "ticket_started" },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("ticket_started");

    // tool_use confirms sticky gate is active
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Bash", command: "ls" },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("ticket_started");

    // Second gate: subagent_invoked → adversarial_review (overwrites sticky)
    await runHook(
      { origin: "soa", kind: "gate", name: "subagent_invoked" },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("adversarial_review");

    // Subsequent tool_use now sticks to adversarial_review
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Bash", command: "ls" },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("adversarial_review");
  });

  // P6.05: workspace_roots fallback
  it("Cursor afterFileEdit with workspace_roots uses workspace_roots[0] for SoA resolution", async () => {
    const projectRoot = mkdtempSync(join(tmpdir(), "codogotchi-cursor-root-"));
    try {
      await mkdir(join(projectRoot, ".soa"), { recursive: true });
      writeFileSync(
        join(projectRoot, ".soa", "events.ndjson"),
        `${JSON.stringify({ name: "ticket_started", ts: "2026-05-18T16:00:00Z" })}\n`,
      );
      // No CLAUDE_PROJECT_DIR or CODEX_PROJECT_DIR — workspace_roots[0] must be used
      await runHook(
        {
          hook_event_name: "afterFileEdit",
          workspace_roots: [projectRoot],
        } as HookInput,
        {
          home,
          now: FIXED_NOW,
          env: {},
          cwd: tmpdir(),
        },
      );
      const state = readState(home);
      // SoA ticket_started event resolved via workspace_roots[0]
      expect(state.activity_state).toBe("ticket_started");
      expect(state.source_event.origin).toBe("soa");
    } finally {
      rmSync(projectRoot, { recursive: true, force: true });
    }
  });
});

describe("runHook + SoA gate precedence", () => {
  let home: string;
  let projectRoot: string;

  beforeEach(async () => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-hook-"));
    projectRoot = mkdtempSync(join(tmpdir(), "codogotchi-soa-root-"));
    await mkdir(home, { recursive: true });
    await mkdir(join(projectRoot, ".soa"), { recursive: true });
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
    rmSync(projectRoot, { recursive: true, force: true });
  });

  it("falls back to tool-call state when .soa/events.ndjson is absent", async () => {
    // projectRoot has .soa/ but no events.ndjson — silent fall-through.
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      {
        home,
        now: FIXED_NOW,
        env: { CLAUDE_PROJECT_DIR: projectRoot },
        cwd: projectRoot,
      },
    );
    const state = readState(home);
    expect(state.activity_state).toBe("implementing");
    expect(state.source_event.origin).toBe("claude_code");
  });

  it("uses the latest fresh SoA event activity state over tool-call state", async () => {
    writeFileSync(
      join(projectRoot, ".soa", "events.ndjson"),
      `${JSON.stringify({
        name: "ticket_started",
        ts: "2026-05-18T16:00:00Z",
      })}\n${JSON.stringify({
        name: "verification_failed",
        ts: "2026-05-18T16:00:01Z",
      })}\n`,
    );
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      {
        home,
        now: FIXED_NOW,
        env: { CLAUDE_PROJECT_DIR: projectRoot },
        cwd: projectRoot,
      },
    );
    const state = readState(home);
    // Latest mapped SoA event wins: verification_failed → errored.
    expect(state.activity_state).toBe("errored");
    expect(state.source_event.origin).toBe("soa");
    expect(state.source_event.kind).toBe("gate");
    expect(state.source_event.name).toBe("verification_failed");
  });

  it("does not re-consume SoA events on the next invocation (tail offset)", async () => {
    writeFileSync(
      join(projectRoot, ".soa", "events.ndjson"),
      `${JSON.stringify({ name: "ticket_started", ts: "2026-05-18T16:00:00Z" })}\n`,
    );
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      {
        home,
        now: FIXED_NOW,
        env: { CLAUDE_PROJECT_DIR: projectRoot },
        cwd: projectRoot,
      },
    );
    // Same file, same content. Second invocation has no fresh SoA events
    // because the tail offset is past the existing line.
    // The sticky gate (ticket_started) persists and overrides the Write heuristic —
    // the source_event stays claude_code, confirming no re-consumption.
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Write" },
      {
        home,
        now: FIXED_NOW,
        env: { CLAUDE_PROJECT_DIR: projectRoot },
        cwd: projectRoot,
      },
    );
    const state = readState(home);
    expect(state.activity_state).toBe("ticket_started");
    expect(state.source_event.origin).toBe("claude_code");
  });

  it("fresh SoA ticket_started overrides Stop standby classification", async () => {
    writeFileSync(
      join(projectRoot, ".soa", "events.ndjson"),
      `${JSON.stringify({ name: "ticket_started", ts: "2026-05-18T16:00:00Z" })}\n`,
    );
    await runHook({ hook_event_name: "Stop" } as HookInput, {
      home,
      now: FIXED_NOW,
      env: { CLAUDE_PROJECT_DIR: projectRoot },
      cwd: projectRoot,
    });
    const state = readState(home);
    expect(state.activity_state).toBe("ticket_started");
    expect(state.source_event.origin).toBe("soa");
    expect(state.source_event.name).toBe("ticket_started");
  });

  it("ignores SoA events with unknown event names", async () => {
    writeFileSync(
      join(projectRoot, ".soa", "events.ndjson"),
      `${JSON.stringify({
        name: "some_unrecognized_event",
        ts: "2026-05-18T16:00:00Z",
      })}\n`,
    );
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      {
        home,
        now: FIXED_NOW,
        env: { CLAUDE_PROJECT_DIR: projectRoot },
        cwd: projectRoot,
      },
    );
    const state = readState(home);
    expect(state.activity_state).toBe("implementing");
    expect(state.source_event.origin).toBe("claude_code");
  });
});

describe("P7.02 §7 pure classifier — [red]", () => {
  it("classifies single Read as reading (not idle)", () => {
    const out = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: 0 },
    );
    // [red] Read ×1 must emit reading, not idle
    expect(out.state).toBe("reading");
    expect(out.readRun).toBe(1);
  });

  it("classifies two consecutive Reads as reading", () => {
    const first = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: 0 },
    );
    const second = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: first.readRun },
    );
    // [red] Read ×2 must still emit reading (streak threshold is ×3 for cramming)
    expect(second.state).toBe("reading");
    expect(second.readRun).toBe(2);
  });

  it("classifies three consecutive Reads as cramming (not thinking)", () => {
    const third = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: 2 },
    );
    // [red] Read ×3+ must emit cramming, not thinking
    expect(third.state).toBe("cramming");
    expect(third.readRun).toBe(3);
  });

  it("classifies Bash 'sed -i' as implementing (write command, not thinking)", () => {
    // [red] sed -i is a write/mutate command; the thinking bucket covers read-only sed
    const out = classifyEvent(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Bash",
        command: "sed -i 's/foo/bar/g' src/index.ts",
      },
      { readRun: 0 },
    );
    expect(out.state).toBe("implementing");
  });

  it("SoA events.ndjson does not override tool-use state after hook-binary drops the reader", async () => {
    // [red] After P7.02 removes resolveSoaRoot/readSoaEventsSince, an Edit event
    // must produce implementing even when a .soa/events.ndjson with ticket_started exists.
    const home = mkdtempSync(join(tmpdir(), "codogotchi-p702-red-"));
    const projectRoot = mkdtempSync(join(tmpdir(), "codogotchi-soa-p702-red-"));
    try {
      await mkdir(home, { recursive: true });
      await mkdir(join(projectRoot, ".soa"), { recursive: true });
      writeFileSync(
        join(projectRoot, ".soa", "events.ndjson"),
        `${JSON.stringify({ name: "ticket_started", ts: "2026-05-18T16:00:00Z" })}\n`,
      );
      await runHook(
        { origin: "claude_code", kind: "tool_use", name: "Edit" },
        {
          home,
          now: FIXED_NOW,
          env: { CLAUDE_PROJECT_DIR: projectRoot },
          cwd: projectRoot,
        },
      );
      const state = readState(home);
      // [red] pure classifier: Edit → implementing, SoA file is ignored
      expect(state.activity_state).toBe("implementing");
      expect(state.source_event.origin).toBe("claude_code");
    } finally {
      rmSync(home, { recursive: true, force: true });
      rmSync(projectRoot, { recursive: true, force: true });
    }
  });
});
