import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  globalAggregate,
  type ProfileResponse,
  type StateJsonV1,
} from "@codogotchi/contracts";
import {
  classifyEvent,
  type HookInput,
  runHook,
  shellCommandSegments,
  sliceDirPath,
  sliceFilePath,
} from "./hook-binary";

const FIXED_NOW = new Date("2026-05-18T15:00:00.000Z");

function readRpgState(home: string): Record<string, unknown> {
  try {
    return JSON.parse(
      readFileSync(join(home, "rpg-state.json"), "utf8"),
    ) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function readState(home: string): StateJsonV1 {
  const dir = sliceDirPath(home);
  let names: string[] = [];
  try {
    names = readdirSync(dir);
  } catch {
    // no state.d/ directory yet
  }
  const slices = names
    .filter((n) => n.endsWith(".json"))
    .map((n) => {
      try {
        return JSON.parse(readFileSync(join(dir, n), "utf8"));
      } catch {
        return null;
      }
    })
    .filter(Boolean);
  return globalAggregate(slices);
}

describe("classifyEvent", () => {
  it("classifies Claude Code Edit tool-use as editing", () => {
    const out = classifyEvent(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Edit",
      },
      { readRun: 0 },
    );
    expect(out.state).toBe("editing");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.kind).toBe("tool_use");
    expect(out.sourceEvent.name).toBe("Edit");
    expect(out.readRun).toBe(0);
  });

  it("classifies Write tool-use as editing", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "tool_use", name: "Write" },
        { readRun: 0 },
      ).state,
    ).toBe("editing");
  });

  it("classifies MultiEdit tool-use as editing", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "tool_use", name: "MultiEdit" },
        { readRun: 0 },
      ).state,
    ).toBe("editing");
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

  it("classifies Bash 'bun run format' as verifying", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "bun run format",
        },
        { readRun: 0 },
      ).state,
    ).toBe("verifying");
  });

  it("classifies Bash 'bun run typecheck' as verifying", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Bash",
          command: "bun run typecheck",
        },
        { readRun: 0 },
      ).state,
    ).toBe("verifying");
  });

  it("classifies xcodebuild build with leading flags as verifying", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command:
            "xcodebuild -project apps/menubar/Codogotchi.xcodeproj -scheme Codogotchi build 2>&1 | tail -25",
        },
        { readRun: 0 },
      ).state,
    ).toBe("verifying");
  });

  it("classifies xcodebuild test with leading flags as testing", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command:
            "xcodebuild -scheme Codogotchi -destination 'platform=macOS' test 2>&1 | tail -20",
        },
        { readRun: 0 },
      ).state,
    ).toBe("testing");
  });

  it("classifies Bash 'git push' as git_ops", () => {
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
    ).toBe("git_ops");
  });

  it("classifies Bash 'grep' as searching", () => {
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
    ).toBe("searching");
  });

  it("classifies Bash 'find' as searching", () => {
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
    ).toBe("searching");
  });

  it("classifies Bash 'rg' as searching", () => {
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
    ).toBe("searching");
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

  it("classifies Bash 'bun run build' as verifying", () => {
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
    ).toBe("verifying");
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

  it("classifies Cursor Shell 'grep' as searching", () => {
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
    ).toBe("searching");
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

  it("searching bucket resets readRun to 0", () => {
    const out = classifyEvent(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Bash",
        command: "grep pattern src/",
      },
      { readRun: 2 },
    );
    expect(out.state).toBe("searching");
    expect(out.readRun).toBe(0);
  });

  it("classifies Read ×1–2 as reading, ×3+ as cramming (§7 streak)", () => {
    const first = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: 0 },
    );
    expect(first.state).toBe("reading");
    expect(first.readRun).toBe(1);

    const second = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: first.readRun },
    );
    expect(second.state).toBe("reading");
    expect(second.readRun).toBe(2);

    const third = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: second.readRun },
    );
    expect(third.state).toBe("cramming");
    expect(third.readRun).toBe(3);
  });

  it("resets Read run when an Edit interrupts", () => {
    const after_edit = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { readRun: 2 },
    );
    expect(after_edit.state).toBe("editing");
    expect(after_edit.readRun).toBe(0);
  });

  it("classifies unknown SoA gate events as thinking (hook no longer reads SoA)", () => {
    // Pure classifier: gate events from origin=soa fall through to thinking since
    // the SoA reader was removed. Gate art is merged from gate.json in the renderer.
    expect(
      classifyEvent(
        { origin: "soa", kind: "gate", name: "ticket_started" },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies session_start with no prior activity as thinking", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "session_start", name: "start" },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies session_end as thinking", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "session_end", name: "end" },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Claude Code raw stdin {tool_name:'Edit'} as editing", () => {
    const out = classifyEvent(
      { tool_name: "Edit", hook_event_name: "PreToolUse" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("editing");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.kind).toBe("tool_use");
    expect(out.sourceEvent.name).toBe("Edit");
  });

  it("classifies Codex raw stdin as codex-origin tool-use", () => {
    const out = classifyEvent(
      { tool_name: "Edit", hook_event_name: "pre_tool_use" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("editing");
    expect(out.sourceEvent.origin).toBe("codex");
    expect(out.sourceEvent.kind).toBe("tool_use");
    expect(out.sourceEvent.name).toBe("Edit");
  });

  it("classifies Codex session_end raw stdin as session_end", () => {
    const out = classifyEvent({ hook_event_name: "session_end" } as HookInput, {
      readRun: 0,
    });
    expect(out.state).toBe("thinking");
    expect(out.sourceEvent.origin).toBe("codex");
    expect(out.sourceEvent.kind).toBe("session_end");
  });

  it("classifies Claude UserPromptSubmit as thinking", () => {
    const out = classifyEvent(
      {
        hook_event_name: "UserPromptSubmit",
        prompt: "do the thing",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("thinking");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.kind).toBe("prompt_submit");
  });

  it("classifies Codex user_prompt_submit as thinking", () => {
    const out = classifyEvent(
      {
        hook_event_name: "user_prompt_submit",
        prompt: "do the thing",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("thinking");
    expect(out.sourceEvent.origin).toBe("codex");
    expect(out.sourceEvent.kind).toBe("prompt_submit");
  });

  it("classifies Cursor beforeSubmitPrompt as thinking", () => {
    const out = classifyEvent(
      {
        hook_event_name: "beforeSubmitPrompt",
        prompt: "do the thing",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("thinking");
    expect(out.sourceEvent.origin).toBe("cursor");
    expect(out.sourceEvent.kind).toBe("prompt_submit");
  });

  it("prompt submit resets readRun — Read×2 → UserPromptSubmit → Read×1 is not cramming", () => {
    const read = {
      origin: "claude_code" as const,
      kind: "tool_use" as const,
      name: "Read",
    };
    const submit = { hook_event_name: "UserPromptSubmit" } as HookInput;
    const r1 = classifyEvent(read, { readRun: 0 });
    const r2 = classifyEvent(read, { readRun: r1.readRun });
    expect(r2.state).toBe("reading");
    const s = classifyEvent(submit, { readRun: r2.readRun });
    expect(s.state).toBe("thinking");
    expect(s.readRun).toBe(0);
    const r3 = classifyEvent(read, { readRun: s.readRun });
    expect(r3.state).toBe("reading");
    expect(r3.readRun).toBe(1);
  });

  it("classifies Stop event as standby", () => {
    const out = classifyEvent({ hook_event_name: "Stop" } as HookInput, {
      readRun: 0,
    });
    expect(out.state).toBe("standby");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.kind).toBe("session_end");
  });

  it("Stop resets readRun to 0 — Read×2 → Stop → Read×1 does not produce cramming", () => {
    const read = {
      origin: "claude_code" as const,
      kind: "tool_use" as const,
      name: "Read",
    };
    const stop = { hook_event_name: "Stop" } as HookInput;
    const r1 = classifyEvent(read, { readRun: 0 });
    expect(r1.state).toBe("reading");
    const r2 = classifyEvent(read, { readRun: r1.readRun });
    expect(r2.state).toBe("reading");
    const s = classifyEvent(stop, { readRun: r2.readRun });
    expect(s.state).toBe("standby");
    expect(s.readRun).toBe(0);
    const r3 = classifyEvent(read, { readRun: s.readRun });
    expect(r3.state).toBe("reading");
    expect(r3.readRun).toBe(1);
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

  it("regression: Edit tool-use classifies as editing (v2 path)", () => {
    const out = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Edit" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("editing");
  });

  // P6.05: Cursor origin fix + shell hooks
  it("Cursor afterFileEdit classifies as editing with cursor origin", () => {
    const out = classifyEvent(
      { hook_event_name: "afterFileEdit" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("editing");
    expect(out.sourceEvent.origin).toBe("cursor");
  });

  it("Cursor beforeShellExecution 'grep' classifies as searching with cursor origin", () => {
    const out = classifyEvent(
      {
        hook_event_name: "beforeShellExecution",
        command: "grep foo",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("searching");
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

  // P9.02: Copilot (vscode) native hook classifier
  describe("Copilot (vscode) native hook classifier", () => {
    let prevOrigin: string | undefined;

    beforeEach(() => {
      prevOrigin = process.env.CODOGOTCHI_ORIGIN;
      process.env.CODOGOTCHI_ORIGIN = "vscode";
    });

    afterEach(() => {
      if (prevOrigin === undefined) delete process.env.CODOGOTCHI_ORIGIN;
      else process.env.CODOGOTCHI_ORIGIN = prevOrigin;
    });

    it("camelCase preToolUse with toolName:'edit' classifies as editing", () => {
      const out = classifyEvent(
        { toolName: "edit", hook_event_name: "preToolUse" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("editing");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    it("snake_case PreToolUse with tool_name:'view' classifies as reading", () => {
      const out = classifyEvent(
        { tool_name: "view", hook_event_name: "PreToolUse" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("reading");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    it("snake_case tool_name and camelCase toolName classify identically for the same tool", () => {
      const snake = classifyEvent(
        { tool_name: "edit", hook_event_name: "PreToolUse" } as HookInput,
        { readRun: 0 },
      );
      const camel = classifyEvent(
        { toolName: "edit", hook_event_name: "preToolUse" } as HookInput,
        { readRun: 0 },
      );
      expect(snake.state).toBe("editing");
      expect(camel.state).toBe(snake.state);
      expect(snake.sourceEvent.origin).toBe("vscode");
      expect(camel.sourceEvent.origin).toBe("vscode");
    });

    it("userPromptSubmitted classifies as prompt_submit / thinking", () => {
      const out = classifyEvent(
        { hook_event_name: "userPromptSubmitted" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("thinking");
      expect(out.sourceEvent.kind).toBe("prompt_submit");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    it("camelCase bash toolName with test-runner command classifies as testing", () => {
      const out = classifyEvent(
        {
          toolName: "bash",
          toolArgs: { command: "bun test" },
          hook_event_name: "preToolUse",
        } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("testing");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    it("agentStop classifies as standby", () => {
      const out = classifyEvent({ hook_event_name: "agentStop" } as HookInput, {
        readRun: 0,
      });
      expect(out.state).toBe("standby");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    it("sessionEnd classifies as standby", () => {
      const out = classifyEvent(
        { hook_event_name: "sessionEnd" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("standby");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    it("errorOccurred classifies as errored", () => {
      const out = classifyEvent(
        { hook_event_name: "errorOccurred" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("errored");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    it("permissionRequest classifies as waiting_for_input", () => {
      const out = classifyEvent(
        { hook_event_name: "permissionRequest" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("waiting_for_input");
      expect(out.sourceEvent.origin).toBe("vscode");
    });

    // Real VS Code Copilot Chat payloads (captured live): Claude-Code-shaped —
    // PascalCase hook_event_name, snake_case tool_name/tool_input, prompt,
    // session_id, transcript_path, cwd. Tool names are VS Code's own vocabulary.
    describe("real payloads (captured live)", () => {
      it("PreToolUse run_in_terminal 'ls -la' → Shell, thinking", () => {
        const out = classifyEvent(
          {
            hook_event_name: "PreToolUse",
            session_id: "S1",
            tool_name: "run_in_terminal",
            tool_input: { command: "ls -la" },
            cwd: "/Users/cesar/code/codogotchi",
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("thinking");
        expect(out.sourceEvent.name).toBe("Shell");
        expect(out.sourceEvent.origin).toBe("vscode");
      });

      it("PreToolUse run_in_terminal 'bun test' → Shell, testing", () => {
        const out = classifyEvent(
          {
            hook_event_name: "PreToolUse",
            tool_name: "run_in_terminal",
            tool_input: { command: "bun test packages/cli" },
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("testing");
        expect(out.sourceEvent.name).toBe("Shell");
      });

      it("PreToolUse read_file → Read, reading", () => {
        const out = classifyEvent(
          {
            hook_event_name: "PreToolUse",
            tool_name: "read_file",
            tool_input: { filePath: "/x/README.md" },
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("reading");
        expect(out.sourceEvent.name).toBe("Read");
      });

      it("PreToolUse grep_search → Grep, searching", () => {
        const out = classifyEvent(
          {
            hook_event_name: "PreToolUse",
            tool_name: "grep_search",
            tool_input: { query: "codogotchi" },
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("searching");
        expect(out.sourceEvent.name).toBe("Grep");
      });

      it("PreToolUse create_file → Write, editing", () => {
        const out = classifyEvent(
          {
            hook_event_name: "PreToolUse",
            tool_name: "create_file",
            tool_input: { filePath: "/x/new.ts" },
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("editing");
        expect(out.sourceEvent.name).toBe("Write");
      });

      it("Stop (hook_event_name 'Stop') → standby", () => {
        const out = classifyEvent(
          {
            hook_event_name: "Stop",
            session_id: "S1",
            stop_hook_active: false,
            cwd: "/Users/cesar/code/codogotchi",
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("standby");
        expect(out.sourceEvent.origin).toBe("vscode");
      });

      it("repo_root comes from cwd via runHook", async () => {
        const home = mkdtempSync(join(tmpdir(), "codogotchi-vscode-run-"));
        await runHook(
          {
            hook_event_name: "PreToolUse",
            tool_name: "read_file",
            tool_input: { filePath: "/x/README.md" },
            cwd: "/Users/cesar/code/codogotchi",
          } as HookInput,
          { home, now: FIXED_NOW },
        );
        const state = readState(home);
        expect(state.source_event?.repo_root).toBe(
          "/Users/cesar/code/codogotchi",
        );
        rmSync(home, { recursive: true, force: true });
      });
    });
  });

  // P9.03: Antigravity native hook classifier
  describe("Antigravity native hook classifier", () => {
    let prevOrigin: string | undefined;

    beforeEach(() => {
      prevOrigin = process.env.CODOGOTCHI_ORIGIN;
      process.env.CODOGOTCHI_ORIGIN = "antigravity";
    });

    afterEach(() => {
      if (prevOrigin === undefined) delete process.env.CODOGOTCHI_ORIGIN;
      else process.env.CODOGOTCHI_ORIGIN = prevOrigin;
    });

    it("PreToolUse write_to_file classifies as editing with antigravity origin", () => {
      const out = classifyEvent(
        {
          toolCall: { name: "write_to_file" },
          hook_event_name: "PreToolUse",
        } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("editing");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("PreToolUse run_command with test-runner CommandLine classifies as testing", () => {
      const out = classifyEvent(
        {
          toolCall: {
            name: "run_command",
            args: { CommandLine: "bun test packages/engine" },
          },
          hook_event_name: "PreToolUse",
        } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("testing");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("PreToolUse run_command with read-only command classifies as searching", () => {
      const out = classifyEvent(
        {
          toolCall: {
            name: "run_command",
            args: { CommandLine: "grep foo src/" },
          },
          hook_event_name: "PreToolUse",
        } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("searching");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("PreToolUse view_file classifies as reading", () => {
      const out = classifyEvent(
        {
          toolCall: { name: "view_file" },
          hook_event_name: "PreToolUse",
        } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("reading");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("PostToolUse with empty error classifies as neutral (thinking)", () => {
      const out = classifyEvent(
        { hook_event_name: "PostToolUse", error: "" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("thinking");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("PostToolUse with non-empty error classifies as errored", () => {
      const out = classifyEvent(
        { hook_event_name: "PostToolUse", error: "exit status 1" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("errored");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("PostToolUse with toolCall.name does not correlate tool metadata", () => {
      const out = classifyEvent(
        {
          hook_event_name: "PostToolUse",
          toolCall: { name: "write_to_file" },
        } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("thinking");
      expect(out.sourceEvent.origin).toBe("antigravity");
      // toolCall.name is scoped to PreToolUse — PostToolUse stays neutral.
      expect(out.sourceEvent.kind).not.toBe("tool_use");
    });

    it("Stop with fullyIdle:true classifies as standby", () => {
      const out = classifyEvent(
        { hook_event_name: "Stop", fullyIdle: true } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("standby");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("Stop with fullyIdle:false does not assert standby (thinking)", () => {
      const out = classifyEvent(
        { hook_event_name: "Stop", fullyIdle: false } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("thinking");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    it("Stop with terminationReason:error classifies as errored", () => {
      const out = classifyEvent(
        { hook_event_name: "Stop", terminationReason: "error" } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("errored");
      expect(out.sourceEvent.origin).toBe("antigravity");
    });

    // Real Antigravity payloads carry NO event-name field — the event is
    // implied by the hooks.json key. These fixtures are the exact shapes
    // captured from a live Antigravity session; the event must be recovered
    // from payload shape alone. Regression guard for the "stuck on thinking"
    // bug where every Antigravity event fell through to the session_start
    // fallthrough because hook_event_name was always absent.
    describe("real payloads (no hook_event_name field)", () => {
      it("PostToolUse (toolCall:null, stepIdx, empty error) → thinking", () => {
        const out = classifyEvent(
          {
            conversationId: "ccb02157",
            error: "",
            stepIdx: 1,
            toolCall: null,
            workspacePaths: ["/Users/cesar/code/codogotchi"],
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("thinking");
        expect(out.sourceEvent.origin).toBe("antigravity");
      });

      it("Stop (fullyIdle:true, terminationReason:ERROR, 429 error) → errored", () => {
        const out = classifyEvent(
          {
            error: "RESOURCE_EXHAUSTED (code 429): Individual quota reached.",
            executionNum: 0,
            fullyIdle: true,
            terminationReason: "ERROR",
            workspacePaths: ["/Users/cesar/code/codogotchi"],
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("errored");
        expect(out.sourceEvent.origin).toBe("antigravity");
      });

      it("clean Stop (fullyIdle:true, terminationReason NO_TOOL_CALL) → standby", () => {
        const out = classifyEvent(
          {
            error: "",
            executionNum: 0,
            fullyIdle: true,
            terminationReason: "NO_TOOL_CALL",
            workspacePaths: ["/Users/cesar/code/codogotchi"],
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("standby");
        expect(out.sourceEvent.origin).toBe("antigravity");
      });

      it("PreToolUse inferred from populated toolCall, no error key (run_command ls) → thinking tool_use", () => {
        const out = classifyEvent(
          {
            stepIdx: 3,
            toolCall: {
              name: "run_command",
              args: {
                CommandLine: "ls -la",
                Cwd: "/Users/cesar/code/codogotchi",
              },
            },
            workspacePaths: ["/Users/cesar/code/codogotchi"],
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("thinking");
        expect(out.sourceEvent.origin).toBe("antigravity");
        expect(out.sourceEvent.kind).toBe("tool_use");
        expect(out.sourceEvent.name).toBe("Shell");
      });

      // Regression: PostToolUse echoes back a POPULATED toolCall alongside its
      // `error` key. The `error`-key check must win over toolCall so this is not
      // misread as PreToolUse (which would drive a tool-use state and, for reads,
      // wrongly bump the cramming read-run counter). Real captured payload.
      it("PostToolUse with populated toolCall + empty error → thinking, not tool_use", () => {
        const out = classifyEvent(
          {
            error: "",
            stepIdx: 3,
            toolCall: {
              name: "run_command",
              args: { CommandLine: "ls -la", toolAction: "List files" },
            },
            workspacePaths: ["/Users/cesar/code/codogotchi"],
          } as HookInput,
          { readRun: 0 },
        );
        expect(out.state).toBe("thinking");
        expect(out.sourceEvent.origin).toBe("antigravity");
        expect(out.sourceEvent.kind).not.toBe("tool_use");
      });

      // A read tool in PostToolUse must NOT advance the read-run streak — only
      // PreToolUse drives tool classification. Guards the cramming counter.
      it("PostToolUse view_file (populated toolCall + error) does not advance read-run", () => {
        const out = classifyEvent(
          {
            error: "",
            stepIdx: 6,
            toolCall: {
              name: "view_file",
              args: { AbsolutePath: "/Users/cesar/code/codogotchi/README.md" },
            },
            workspacePaths: ["/Users/cesar/code/codogotchi"],
          } as HookInput,
          { readRun: 2 },
        );
        expect(out.state).toBe("thinking");
        expect(out.readRun).toBe(0);
      });
    });
  });
});

describe("runHook", () => {
  let home: string;

  beforeEach(async () => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-hook-"));
    await mkdir(home, { recursive: true });
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("writes slice on first event with default thriving overlay when no profile", async () => {
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.schema_version).toBe(8);
    expect(state.activity_state).toBe("editing");
    expect(state.hp).toBe(100);
    expect(state.hp_overlay).toBe("thriving");
    expect(state.updated_at).toBe(FIXED_NOW.toISOString());
    expect(state.source_event.name).toBe("Edit");
    expect(state.source_event.repo_root).toBe(process.cwd());
  });

  it("writes source_event.repo_root from Cursor workspace_roots when present", async () => {
    const repoRoot = join(tmpdir(), "codogotchi-workspace-root");
    await runHook(
      {
        hook_event_name: "beforeShellExecution",
        tool_input: { command: "bun test" },
        workspace_roots: [repoRoot],
      },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.source_event.origin).toBe("cursor");
    expect(state.source_event.repo_root).toBe(repoRoot);
  });

  it("writes antigravity Stop repo_root from workspacePaths and errored state (real payload)", async () => {
    const repoRoot = join(tmpdir(), "codogotchi-ag-workspace");
    await runHook(
      {
        origin: "antigravity",
        error: "RESOURCE_EXHAUSTED (code 429): Individual quota reached.",
        executionNum: 0,
        fullyIdle: true,
        terminationReason: "ERROR",
        workspacePaths: [repoRoot],
      } as HookInput,
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    // Inferred from shape (no hook_event_name); repo_root from camelCase
    // workspacePaths, not PWD.
    expect(state.source_event.origin).toBe("antigravity");
    expect(state.source_event.repo_root).toBe(repoRoot);
    expect(state.activity_state).toBe("errored");
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

  it("SoA gate events produce thinking (hook no longer reads SoA events)", async () => {
    await runHook(
      { origin: "soa", kind: "gate", name: "ticket_completed" },
      { home, now: FIXED_NOW },
    );
    expect(readState(home).activity_state).toBe("thinking");
  });

  it("tracks consecutive Read runs across invocations: ×1–2 reading, ×3 cramming", async () => {
    const input: HookInput = {
      origin: "claude_code",
      kind: "tool_use",
      name: "Read",
    };
    await runHook(input, { home, now: FIXED_NOW });
    expect(readState(home).activity_state).toBe("reading");

    await runHook(input, { home, now: FIXED_NOW });
    expect(readState(home).activity_state).toBe("reading");

    await runHook(input, { home, now: FIXED_NOW });
    expect(readState(home).activity_state).toBe("cramming");
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

    expect(readState(home).activity_state).toBe("cramming");
  });

  it("breaks a stale .hook.lock left by a killed hook and still writes slice", async () => {
    // A hook killed mid-write never reaches the `finally` rmdir, so the lock dir
    // is left behind. Without stale recovery this would time out every later
    // write and freeze the pet. Simulate it: an old, never-released lock dir.
    const lockPath = join(home, ".hook.lock");
    mkdirSync(lockPath);
    const stale = new Date(Date.now() - 60_000); // 60s old → past LOCK_STALE_MS
    utimesSync(lockPath, stale, stale);

    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );

    expect(readState(home).activity_state).toBe("editing");
    // Lock was broken, acquired, and released again on the way out.
    expect(existsSync(lockPath)).toBe(false);
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
    // One Read after reset → reading (not idle; §7 Read ×1 = reading).
    expect(readState(home).activity_state).toBe("reading");
  });

  it("writes STATE_JSON_SCHEMA_VERSION for a Stop event", async () => {
    await runHook({ hook_event_name: "Stop" } as HookInput, {
      home,
      now: FIXED_NOW,
    });
    const state = readState(home);
    expect(state.schema_version).toBe(8);
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
    const sessionId = "ses-atomic";
    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Edit",
        session_id: sessionId,
      },
      { home, now: FIXED_NOW },
    );
    // Sanity: slice file is fully parseable.
    const slicePath = sliceFilePath(home, "claude_code", sessionId);
    const raw = readFileSync(slicePath, "utf8");
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

  it("Stop after UserPromptSubmit uses truncated prompt as attention.summary", async () => {
    const sessionId = "session-abc";
    const prompt =
      "Refactor the auth module to use the new token store immediately";
    await runHook(
      {
        hook_event_name: "UserPromptSubmit",
        session_id: sessionId,
        prompt,
      } as HookInput,
      { home, now: FIXED_NOW },
    );
    await runHook(
      { hook_event_name: "Stop", session_id: sessionId } as HookInput,
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    expect(state.attention?.reason_kind).toBe("input_requested");
    expect(state.attention?.summary).toBe(
      "Refactor the auth module to use the new token store immediately",
    );
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
    expect(state.attention?.summary).toBe("Something went wrong");
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
});

describe("P7.02 §7 pure classifier", () => {
  it("classifies single Read as reading (not idle)", () => {
    const out = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: 0 },
    );
    // Read ×1 must emit reading, not idle
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
    // Read ×2 must still emit reading (streak threshold is ×3 for cramming)
    expect(second.state).toBe("reading");
    expect(second.readRun).toBe(2);
  });

  it("classifies three consecutive Reads as cramming (not thinking)", () => {
    const third = classifyEvent(
      { origin: "claude_code", kind: "tool_use", name: "Read" },
      { readRun: 2 },
    );
    // Read ×3+ must emit cramming, not thinking
    expect(third.state).toBe("cramming");
    expect(third.readRun).toBe(3);
  });

  it("classifies Bash 'sed -i' as implementing (write command, not thinking)", () => {
    // sed -i is a write/mutate command; sed is not in §7 thinking list
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

  it("classifies Bash 'sed -n' as thinking (read-only slice)", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command:
            "sed -n '220,360p' /Users/cesar/code/codogotchi/apps/menubar/Sources/AttentionBubblePanel.swift",
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'git status' as git_ops", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command: "git status --short",
        },
        { readRun: 0 },
      ).state,
    ).toBe("git_ops");
  });

  it("classifies Bash 'pgrep' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command: "pgrep -fl Codogotchi || true",
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'xcodebuild -list' as thinking", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command:
            "xcodebuild -list -project /Users/cesar/code/codogotchi/apps/menubar/Menubar.xcodeproj",
        },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("classifies Bash 'swift test' as testing", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command: "swift test --filter TransitionLogTests",
        },
        { readRun: 0 },
      ).state,
    ).toBe("testing");
  });

  it("classifies Bash 'xcodebuild test' as testing", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command:
            "xcodebuild test -project /Users/cesar/code/codogotchi/apps/menubar/Codogotchi.xcodeproj -scheme Codogotchi -destination 'platform=macOS'",
        },
        { readRun: 0 },
      ).state,
    ).toBe("testing");
  });

  it("classifies Codex apply_patch as editing", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "apply_patch",
        },
        { readRun: 0 },
      ).state,
    ).toBe("editing");
  });

  it("classifies Cursor Grep tool as searching", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Grep",
        },
        { readRun: 0 },
      ).state,
    ).toBe("searching");
  });

  it("classifies Cursor Glob tool as searching", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Glob",
        },
        { readRun: 0 },
      ).state,
    ).toBe("searching");
  });

  it("classifies ToolSearch as web_search", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "tool_use", name: "ToolSearch" },
        { readRun: 0 },
      ).state,
    ).toBe("web_search");
  });

  it("classifies Skill as web_search", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "tool_use", name: "Skill" },
        { readRun: 0 },
      ).state,
    ).toBe("web_search");
  });

  it("classifies MCP tools (mcp__ prefix) as web_search", () => {
    expect(
      classifyEvent(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "mcp__plugin_context7_context7__query-docs",
        },
        { readRun: 0 },
      ).state,
    ).toBe("web_search");
  });

  it("classifies compound shell with git status as git_ops", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command:
            "git branch --show-current && git status --short && git remote -v",
        },
        { readRun: 0 },
      ).state,
    ).toBe("git_ops");
  });

  it("classifies compound shell with rg after cd as searching", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command: "cd /repo && rg -n 'classifyEvent' packages/cli",
        },
        { readRun: 0 },
      ).state,
    ).toBe("searching");
  });

  it("classifies Codex postToolUse apply_patch (name only) as editing", () => {
    const out = classifyEvent(
      { name: "apply_patch", hook_event_name: "postToolUse" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("editing");
    expect(out.sourceEvent.kind).toBe("tool_use");
    expect(out.sourceEvent.name).toBe("apply_patch");
  });

  it("classifies bun run mac:test as testing", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command: "bun run mac:test",
        },
        { readRun: 0 },
      ).state,
    ).toBe("testing");
  });

  it("classifies bun run verify:quiet as verifying", () => {
    expect(
      classifyEvent(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Bash",
          command: "bun run verify:quiet",
        },
        { readRun: 0 },
      ).state,
    ).toBe("verifying");
  });

  it("classifies standalone git add as git_ops", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command: "git add packages/cli/src/hook-binary.ts",
        },
        { readRun: 0 },
      ).state,
    ).toBe("git_ops");
  });

  it("classifies background cd then git commit as git_ops", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command: "cd /repo & git commit -m test",
        },
        { readRun: 0 },
      ).state,
    ).toBe("git_ops");
  });

  it("classifies piped test runner by left-hand command", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command: "bun test packages/cli 2>&1 | tail -20",
        },
        { readRun: 0 },
      ).state,
    ).toBe("testing");
  });

  it("classifies piped verify runner by left-hand command", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command: "bun run verify:quiet 2>&1 | tail -6",
        },
        { readRun: 0 },
      ).state,
    ).toBe("verifying");
  });

  it("classifies git commit after format and add segments as git_ops", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command:
            "cd /repo; bun run format >/dev/null 2>&1; git add docs/ledger.jsonl && git commit -q -m docs",
        },
        { readRun: 0 },
      ).state,
    ).toBe("git_ops");
  });

  it("classifies grep commit compound as git_ops over searching", () => {
    expect(
      classifyEvent(
        {
          origin: "cursor",
          kind: "tool_use",
          name: "Shell",
          command: "grep foo && git commit -m test",
        },
        { readRun: 0 },
      ).state,
    ).toBe("git_ops");
  });

  it("classifies unknown tool_use as thinking (global fallback)", () => {
    expect(
      classifyEvent(
        { origin: "claude_code", kind: "tool_use", name: "SomeFutureTool" },
        { readRun: 0 },
      ).state,
    ).toBe("thinking");
  });

  it("SoA events.ndjson does not override tool-use state after hook-binary drops the reader", async () => {
    // After P7.02 removes resolveSoaRoot/readSoaEventsSince, an Edit event
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
        { home, now: FIXED_NOW },
      );
      const state = readState(home);
      // pure classifier: Edit → editing; .soa/events.ndjson is never read
      expect(state.activity_state).toBe("editing");
      expect(state.source_event.origin).toBe("claude_code");
    } finally {
      rmSync(home, { recursive: true, force: true });
      rmSync(projectRoot, { recursive: true, force: true });
    }
  });
});

describe("shellCommandSegments", () => {
  it("splits on &&, ;, newline, and single &", () => {
    expect(shellCommandSegments("cd /repo && git commit -m x")).toEqual([
      "git commit -m x",
    ]);
    expect(shellCommandSegments("cd /repo; git status")).toEqual([
      "git status",
    ]);
    expect(shellCommandSegments("cd /repo & git commit -m x")).toEqual([
      "git commit -m x",
    ]);
    expect(shellCommandSegments("cd /repo\ngit status --short")).toEqual([
      "git status --short",
    ]);
  });

  it("splits pipes and strips neutral cd/echo segments", () => {
    expect(
      shellCommandSegments(
        'ls -la /tmp/memory 2>&1; echo "---"; grep -ril "quality" /tmp/memory 2>&1',
      ),
    ).toEqual([
      "ls -la /tmp/memory 2>&1",
      'grep -ril "quality" /tmp/memory 2>&1',
    ]);
    expect(
      shellCommandSegments("bun test packages/cli 2>&1 | tail -20"),
    ).toEqual(["bun test packages/cli 2>&1", "tail -20"]);
  });

  it("does not split shell redirects like 2>&1 on single &", () => {
    expect(shellCommandSegments("git push 2>&1")).toEqual(["git push 2>&1"]);
  });

  it("preserves a lone command when every segment is neutral", () => {
    expect(shellCommandSegments("cd /repo")).toEqual(["cd /repo"]);
  });

  it("does not split on a | inside a quoted regex/glob argument", () => {
    // Real commands from ~/.codogotchi/state-transitions.log that were
    // shredded mid-regex by the quote-blind pipe splitter and fell through to
    // the `implementing` catch-all instead of `searching`.
    expect(shellCommandSegments("rg -n 'sizes\\.|fileSizes' .")).toEqual([
      "rg -n 'sizes\\.|fileSizes' .",
    ]);
    expect(
      shellCommandSegments(
        "rg -n 'createOrUpdateUser|existingUserId' node_modules -g '*.ts'",
      ),
    ).toEqual([
      "rg -n 'createOrUpdateUser|existingUserId' node_modules -g '*.ts'",
    ]);
    expect(
      shellCommandSegments('grep -n "db.query.*users\\|from_users" convex/ -r'),
    ).toEqual(['grep -n "db.query.*users\\|from_users" convex/ -r']);
  });

  it("still splits a real pipe that follows a quoted argument", () => {
    expect(
      shellCommandSegments("rg --files convex test | rg '^(convex/schema.ts)'"),
    ).toEqual(["rg --files convex test", "rg '^(convex/schema.ts)'"]);
  });
});

// ---------------------------------------------------------------------------
// P13.01 Red tests — rpg-state.json separation
// runHook must write rpg-state.json with RPG fields and omit them from slices.
// These tests MUST fail until the implementation is in place.
// ---------------------------------------------------------------------------
describe("P13.01 rpg-state.json separation (red)", () => {
  let home: string;
  let claudeRoot: string;
  const origClaudeRoot = process.env.CODOGOTCHI_CLAUDE_ROOT;
  const origCodexRoot = process.env.CODOGOTCHI_CODEX_ROOT;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-p1301-"));
    claudeRoot = join(home, "claude-sessions");
    mkdirSync(claudeRoot, { recursive: true });
    process.env.CODOGOTCHI_CLAUDE_ROOT = claudeRoot;
    process.env.CODOGOTCHI_CODEX_ROOT = join(home, "codex-sessions");
    writeFileSync(
      join(home, "config.json"),
      JSON.stringify({
        profile_id: "test-profile",
        features: { rpg_enabled: true },
      }),
    );
    // Pre-seed XP cache so computeAndPersistV5Fields runs its incremental path.
    const cursorBeforeFixture = new Date(
      new Date(FIXTURE_EVENT_TS).getTime() - 1000,
    ).toISOString();
    writeFileSync(
      join(home, ".local-xp-cache.json"),
      JSON.stringify({ last_read_at_claude: cursorBeforeFixture }),
    );
    // One fixture JSONL with tokens to drive level computation.
    const projDir = join(claudeRoot, "fixture-project");
    mkdirSync(projDir, { recursive: true });
    writeFileSync(join(projDir, "transcript.jsonl"), `${FIXTURE_JSONL_LINE}\n`);
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
    if (origClaudeRoot === undefined) delete process.env.CODOGOTCHI_CLAUDE_ROOT;
    else process.env.CODOGOTCHI_CLAUDE_ROOT = origClaudeRoot;
    if (origCodexRoot === undefined) delete process.env.CODOGOTCHI_CODEX_ROOT;
    else process.env.CODOGOTCHI_CODEX_ROOT = origCodexRoot;
  });

  it("runHook with rpg_enabled writes rpg-state.json with level/half_hearts; slice has neither", async () => {
    const sessionId = "ses-p1301";
    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Edit",
        session_id: sessionId,
      },
      { home, now: FIXED_NOW },
    );

    // rpg-state.json must exist and carry RPG fields
    const rpgPath = join(home, "rpg-state.json");
    expect(existsSync(rpgPath)).toBe(true);
    const rpg = JSON.parse(readFileSync(rpgPath, "utf8"));
    expect(typeof rpg.level).toBe("number");
    expect(typeof rpg.half_hearts).toBe("number");

    // slice file must NOT contain RPG fields (they moved to rpg-state.json)
    const slicePath = sliceFilePath(home, "claude_code", sessionId);
    expect(existsSync(slicePath)).toBe(true);
    const slice = JSON.parse(readFileSync(slicePath, "utf8"));
    expect(slice.level).toBeUndefined();
    expect(slice.half_hearts).toBeUndefined();
    expect(slice.level_fraction).toBeUndefined();
    expect(slice.active_minutes).toBeUndefined();
    expect(slice.last_activity_at).toBeUndefined();
    expect(slice.revive_until).toBeUndefined();
  });

  it("migration seed: v7 slice with half_hearts:4 level:3 seeds rpg-state.json on first runHook", async () => {
    // Plant a v7 slice in state.d/ (last-writer-wins seed source).
    const sliceDir = join(home, "state.d");
    mkdirSync(sliceDir, { recursive: true });
    const v7Slice = {
      schema_version: 7,
      origin: "claude_code",
      session_id: "seed-session",
      activity_state: "idle",
      hp_overlay: "thriving",
      hp: 100,
      updated_at: "2026-06-27T12:00:00.000Z",
      source_event: { origin: "claude_code", kind: "cli", name: "test" },
      level: 3,
      level_fraction: 0.25,
      half_hearts: 4,
      active_minutes: 10,
      last_activity_at: "2026-06-27T12:00:00.000Z",
    };
    writeFileSync(
      join(sliceDir, "claude_code:seed-session.json"),
      JSON.stringify(v7Slice),
      "utf8",
    );

    // rpg-state.json must not exist yet
    expect(existsSync(join(home, "rpg-state.json"))).toBe(false);

    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Edit",
        session_id: "new-session",
      },
      { home, now: FIXED_NOW },
    );

    // rpg-state.json must be seeded from the v7 slice.
    // Pin level_fraction and active_minutes too — they uniquely identify the
    // seed path (v5-computed values cannot yield 0.25 and 10 simultaneously).
    const rpgPath = join(home, "rpg-state.json");
    expect(existsSync(rpgPath)).toBe(true);
    const rpg = JSON.parse(readFileSync(rpgPath, "utf8"));
    expect(rpg.level).toBe(3);
    expect(rpg.half_hearts).toBe(4);
    expect(rpg.level_fraction).toBe(0.25);
    expect(rpg.active_minutes).toBe(10);
  });
});

describe("quoted-pipe search commands classify as searching", () => {
  // Regression for the quote-blind splitShellPipes bug: search-intent commands
  // whose regex/glob contained `|` were misrouted to `implementing`.
  const searchCommands = [
    "rg -n 'createOrUpdateUser|existingUserId' node_modules -g '*.ts'",
    'rg -n "validateAndRepackPet|sizes|zipStorageId" convex test docs',
    "rg -n 'sizes\\.|fileSizes' .",
    'grep -n "db.query.*users\\|from_users" /repo/convex/ -r 2>&1',
    'grep -r "convex-dev/auth\\|convex_dev_auth" /repo/ --include="*.ts" -l',
  ];
  for (const command of searchCommands) {
    it(`classifies ${command.slice(0, 48)}… as searching`, () => {
      const out = classifyEvent(
        {
          hook_event_name: "PreToolUse",
          tool_name: "Bash",
          tool_input: { command },
        } as HookInput,
        { readRun: 0 },
      );
      expect(out.state).toBe("searching");
    });
  }
});

describe("P7.03 terminal failure parity", () => {
  it("classifies Claude Code StopFailure (rate_limit) as errored", () => {
    const out = classifyEvent(
      { hook_event_name: "StopFailure", error: "rate_limit" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("errored");
  });

  it("classifies Claude Code StopFailure (any error value) as errored", () => {
    const out = classifyEvent(
      { hook_event_name: "StopFailure", error: "server_error" } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("errored");
  });

  it("classifies Cursor stop with status:error as errored", () => {
    const out = classifyEvent(
      {
        hook_event_name: "stop",
        status: "error",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("errored");
  });

  it("classifies Cursor postToolUseFailure (is_interrupt:false) as errored", () => {
    const out = classifyEvent(
      {
        hook_event_name: "postToolUseFailure",
        is_interrupt: false,
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("errored");
  });

  it("classifies Cursor postToolUseFailure (is_interrupt:true) as idle", () => {
    const out = classifyEvent(
      {
        hook_event_name: "postToolUseFailure",
        is_interrupt: true,
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("idle");
    expect(out.state).not.toBe("errored");
  });

  it("classifies Claude PostToolUseFailure (is_interrupt:true) as idle", () => {
    const out = classifyEvent(
      {
        hook_event_name: "PostToolUseFailure",
        is_interrupt: true,
        tool_name: "Bash",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("idle");
    expect(out.state).not.toBe("implementing");
  });

  it("classifies Cursor stop with status:aborted as idle", () => {
    const out = classifyEvent(
      {
        hook_event_name: "stop",
        status: "aborted",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("idle");
  });

  it("classifies Copilot sessionEnd with reason:abort as idle", () => {
    const out = classifyEvent(
      {
        hook_event_name: "sessionEnd",
        reason: "abort",
        origin: "vscode",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("idle");
  });

  it("normal Stop success still produces standby (no regression)", () => {
    const out = classifyEvent({ hook_event_name: "Stop" } as HookInput, {
      readRun: 0,
    });
    expect(out.state).toBe("standby");
  });
});

describe("waiting_for_input permission hooks", () => {
  it("classifies Claude PermissionRequest as waiting_for_input", () => {
    const out = classifyEvent(
      {
        hook_event_name: "PermissionRequest",
        tool_name: "Bash",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("waiting_for_input");
    expect(out.sourceEvent.origin).toBe("claude_code");
    expect(out.sourceEvent.name).toBe("Bash");
  });

  it("classifies Codex permission_request as waiting_for_input", () => {
    const out = classifyEvent(
      {
        hook_event_name: "permission_request",
        tool_name: "Write",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("waiting_for_input");
    expect(out.sourceEvent.origin).toBe("codex");
    expect(out.sourceEvent.name).toBe("Write");
  });

  it("classifies Cursor beforeMCPExecution as waiting_for_input", () => {
    const out = classifyEvent(
      {
        hook_event_name: "beforeMCPExecution",
        tool_name: "mcp__context7__query",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("waiting_for_input");
    expect(out.sourceEvent.origin).toBe("cursor");
    expect(out.sourceEvent.name).toBe("mcp__context7__query");
  });

  it("Cursor beforeShellExecution still classifies shell activity (not waiting)", () => {
    const out = classifyEvent(
      {
        hook_event_name: "beforeShellExecution",
        command: "grep foo",
      } as HookInput,
      { readRun: 0 },
    );
    expect(out.state).toBe("searching");
    expect(out.sourceEvent.origin).toBe("cursor");
  });

  it("runHook writes waiting_for_input with attention payload", async () => {
    const home = mkdtempSync(join(tmpdir(), "codogotchi-waiting-"));
    try {
      await runHook(
        {
          hook_event_name: "PermissionRequest",
          tool_name: "Edit",
        } as HookInput,
        { home, now: FIXED_NOW },
      );
      const state = readState(home);
      expect(state.activity_state).toBe("waiting_for_input");
      expect(state.attention?.reason_kind).toBe("input_requested");
      expect(state.attention?.summary).toBe("Approval required");
      expect(state.source_event.name).toBe("Edit");
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });
});

// Fixture JSONL line with 1,000,000 tokens (500k input + 500k output).
// Event timestamp is 60 s before FIXED_NOW so it falls within the `since=epoch`
// first-read window but before the cursor stored after that read (= FIXED_NOW),
// ensuring the no-double-count assertion holds for any `since ≥ FIXED_NOW`.
const FIXTURE_EVENT_TS = new Date(
  new Date("2026-05-18T15:00:00.000Z").getTime() - 60_000,
).toISOString();
const FIXTURE_JSONL_LINE = JSON.stringify({
  timestamp: FIXTURE_EVENT_TS,
  cwd: "/fixture/project",
  message: { usage: { input_tokens: 500_000, output_tokens: 500_000 } },
});
// Expected level for 1,000,000 XP (1 XP per token, claude only).
const EXPECTED_LEVEL = 2;
const EXPECTED_LEVEL_FRACTION = 0.09321718114555341;

describe("runHook v5 local RPG fields", () => {
  let home: string;
  let claudeRoot: string;
  const origClaudeRoot = process.env.CODOGOTCHI_CLAUDE_ROOT;
  const origCodexRoot = process.env.CODOGOTCHI_CODEX_ROOT;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-v5-"));
    claudeRoot = join(home, "claude-sessions");
    mkdirSync(claudeRoot, { recursive: true });
    // Point readers at temp dirs so no real ~/.claude or ~/.codex is touched.
    process.env.CODOGOTCHI_CLAUDE_ROOT = claudeRoot;
    process.env.CODOGOTCHI_CODEX_ROOT = join(home, "codex-sessions");
    // Config with rpg_enabled: true but no cloud fields (local-RPG mode).
    writeFileSync(
      join(home, "config.json"),
      JSON.stringify({
        profile_id: "test-profile",
        features: { rpg_enabled: true },
      }),
    );
    // Pre-seed cache with cursor just before the fixture event so the tests
    // exercise the incremental-read path (cursor already initialized, event
    // arrives after cursor). Without this the first run would skip historical
    // tokens as intended for a real fresh install.
    const cursorBeforeFixture = new Date(
      new Date(FIXTURE_EVENT_TS).getTime() - 1000,
    ).toISOString();
    writeFileSync(
      join(home, ".local-xp-cache.json"),
      JSON.stringify({ last_read_at_claude: cursorBeforeFixture }),
    );
    // Single fixture JSONL file with 1,000,000 tokens.
    const projDir = join(claudeRoot, "fixture-project");
    mkdirSync(projDir, { recursive: true });
    writeFileSync(join(projDir, "transcript.jsonl"), `${FIXTURE_JSONL_LINE}\n`);
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
    if (origClaudeRoot === undefined) delete process.env.CODOGOTCHI_CLAUDE_ROOT;
    else process.env.CODOGOTCHI_CLAUDE_ROOT = origClaudeRoot;
    if (origCodexRoot === undefined) delete process.env.CODOGOTCHI_CODEX_ROOT;
    else process.env.CODOGOTCHI_CODEX_ROOT = origCodexRoot;
  });

  it("claude hook event writes v8 rpg-state.json with level, level_fraction, half_hearts, last_activity_at", async () => {
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    const rpg = readRpgState(home);
    expect(state.schema_version).toBe(8);
    expect(rpg.level).toBe(EXPECTED_LEVEL);
    expect(rpg.level_fraction as number).toBeCloseTo(
      EXPECTED_LEVEL_FRACTION,
      6,
    );
    expect(rpg.half_hearts).toBe(6);
    expect(rpg.last_activity_at).toBe(FIXED_NOW.toISOString());
    // Revival-meter source: active-minute carry is now surfaced via rpg-state.json.
    expect(rpg.active_minutes).toBe(1);
    // Slice must NOT carry RPG fields.
    expect(state.level).toBeUndefined();
    expect(state.half_hearts).toBeUndefined();
  });

  it("second identical run does not increase XP (no double count)", async () => {
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const rpg1 = readRpgState(home);
    expect(rpg1.level).toBe(EXPECTED_LEVEL);

    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const rpg2 = readRpgState(home);

    expect(rpg2.level).toBe(EXPECTED_LEVEL);
    expect(rpg2.level_fraction).toBe(rpg1.level_fraction);
  });

  it("cursor-origin event updates last_activity_at but leaves level unchanged", async () => {
    // Establish XP with a claude event first.
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const rpgAfterClaude = readRpgState(home);

    const laterNow = new Date(FIXED_NOW.getTime() + 30_000);
    await runHook(
      { hook_event_name: "beforeShellExecution" }, // cursor origin
      { home, now: laterNow },
    );
    const rpgAfterCursor = readRpgState(home);

    expect(rpgAfterCursor.last_activity_at).toBe(laterNow.toISOString());
    expect(rpgAfterCursor.level).toBe(rpgAfterClaude.level);
    expect(rpgAfterCursor.level_fraction).toBe(rpgAfterClaude.level_fraction);
  });

  it("succeeds with rpg_enabled:true but no cloud config (no convex_http_url)", async () => {
    // Config already has rpg_enabled:true, no handle or convex_http_url — local-RPG mode.
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    const state = readState(home);
    const rpg = readRpgState(home);
    expect(state.schema_version).toBe(8);
    expect(rpg.level).toBeDefined();
    expect(rpg.half_hearts).toBeDefined();
    expect(rpg.last_activity_at).toBeDefined();
  });

  it("credits at most one active-minute per wall-clock minute (heal unit is a minute, not a hook event)", async () => {
    const readActiveMinutes = (): number =>
      JSON.parse(readFileSync(join(home, ".local-xp-cache.json"), "utf8"))
        .active_minutes;

    // Three hook events inside the same minute earn exactly 1 active-minute.
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: FIXED_NOW },
    );
    expect(readActiveMinutes()).toBe(1);

    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: new Date(FIXED_NOW.getTime() + 5_000) },
    );
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: new Date(FIXED_NOW.getTime() + 59_999) },
    );
    expect(readActiveMinutes()).toBe(1);

    // An event a full minute past the last credit earns the next active-minute.
    await runHook(
      { origin: "claude_code", kind: "tool_use", name: "Edit" },
      { home, now: new Date(FIXED_NOW.getTime() + 60_000) },
    );
    expect(readActiveMinutes()).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// P12.02 Red tests — slice-directory writer
// These tests import sliceFilePath which does not exist yet; they MUST fail
// until the implementation is in place.
// ---------------------------------------------------------------------------
describe("slice-directory writer (P12.02 red)", () => {
  let home: string;

  beforeEach(async () => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-slice-"));
    await mkdir(home, { recursive: true });
    // Write minimal config so runHook doesn't bail early.
    writeFileSync(
      join(home, ".codogotchi.json"),
      JSON.stringify({ rpg_enabled: false }),
      "utf8",
    );
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("single hook event writes exactly one slice file at state.d/<origin>:<session_id>.json", async () => {
    const sessionId = "ses-001";
    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Edit",
        session_id: sessionId,
      },
      { home, now: FIXED_NOW },
    );
    const expected = sliceFilePath(home, "claude_code", sessionId);
    expect(existsSync(expected)).toBe(true);
    const slice = JSON.parse(readFileSync(expected, "utf8"));
    expect(slice.schema_version).toBe(8);
    expect(slice.origin).toBe("claude_code");
    expect(slice.session_id).toBe(sessionId);
    expect(slice.activity_state).toBeDefined();
    // state.json must NOT exist (slice-dir replaces it)
    expect(existsSync(join(home, "state.json"))).toBe(false);
  });

  it("concurrent-write: two origins produce two independent slice files (proves same-process async I/O interleaving)", async () => {
    const sidA = "ses-claude-001";
    const sidB = "ses-codex-001";

    await Promise.all([
      runHook(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Write",
          session_id: sidA,
        },
        { home, now: FIXED_NOW },
      ),
      runHook(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Write",
          session_id: sidB,
        },
        { home, now: FIXED_NOW },
      ),
    ]);

    const pathA = sliceFilePath(home, "claude_code", sidA);
    const pathB = sliceFilePath(home, "codex", sidB);

    expect(existsSync(pathA)).toBe(true);
    expect(existsSync(pathB)).toBe(true);

    const sliceA = JSON.parse(readFileSync(pathA, "utf8"));
    const sliceB = JSON.parse(readFileSync(pathB, "utf8"));

    expect(sliceA.origin).toBe("claude_code");
    expect(sliceB.origin).toBe("codex");
    expect(sliceA.session_id).toBe(sidA);
    expect(sliceB.session_id).toBe(sidB);
  });

  it("session_end removes that origin/session slice file but leaves other origins intact", async () => {
    const sidA = "ses-claude-end";
    const sidB = "ses-codex-keep";

    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Read",
        session_id: sidA,
      },
      { home, now: FIXED_NOW },
    );
    await runHook(
      { origin: "codex", kind: "tool_use", name: "Read", session_id: sidB },
      { home, now: FIXED_NOW },
    );

    const pathA = sliceFilePath(home, "claude_code", sidA);
    const pathB = sliceFilePath(home, "codex", sidB);
    expect(existsSync(pathA)).toBe(true);
    expect(existsSync(pathB)).toBe(true);

    // session_end for claude_code session
    await runHook(
      {
        origin: "claude_code",
        hook_event_name: "session_end",
        session_id: sidA,
      } as HookInput,
      { home, now: new Date(FIXED_NOW.getTime() + 1000) },
    );

    expect(existsSync(pathA)).toBe(false);
    expect(existsSync(pathB)).toBe(true);
  });

  it("writes active-session.json inside the detected repository root", async () => {
    const sessionId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
    await runHook(
      {
        origin: "claude_code",
        kind: "tool_use",
        name: "Edit",
        session_id: sessionId,
        cwd: home,
      },
      { home, now: FIXED_NOW },
    );

    const activeSessionPath = join(home, ".soa", "active-session.json");
    expect(existsSync(activeSessionPath)).toBe(true);
    const content = JSON.parse(readFileSync(activeSessionPath, "utf8"));
    expect(content.origin).toBe("claude_code");
    expect(content.session_id).toBe(sessionId);
    expect(content.updated_at).toBe(FIXED_NOW.toISOString());
  });

  it("writes active-session.json to the main root when cwd is a linked worktree", async () => {
    // Real linked-worktree layout: main checkout has a `.git` directory; the
    // worktree has a `.git` file pointing at the main's worktrees dir. SoA reads
    // active-session.json from the canonical main root, so the hook must write
    // there too — not into the worktree's own .soa/.
    const repoParent = mkdtempSync(join(tmpdir(), "codogotchi-wt-"));
    try {
      const mainRoot = join(repoParent, "codogotchi");
      const worktree = join(repoParent, "codogotchi_p13_04");
      mkdirSync(join(mainRoot, ".git", "worktrees", "codogotchi_p13_04"), {
        recursive: true,
      });
      mkdirSync(worktree, { recursive: true });
      writeFileSync(
        join(worktree, ".git"),
        `gitdir: ${join(mainRoot, ".git", "worktrees", "codogotchi_p13_04")}\n`,
        "utf8",
      );

      await runHook(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Edit",
          session_id: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff",
          cwd: worktree,
        },
        { home, now: FIXED_NOW },
      );

      // Lands at the main root, NOT the worktree.
      const mainActiveSession = join(mainRoot, ".soa", "active-session.json");
      const worktreeActiveSession = join(
        worktree,
        ".soa",
        "active-session.json",
      );
      expect(existsSync(mainActiveSession)).toBe(true);
      expect(existsSync(worktreeActiveSession)).toBe(false);
      const content = JSON.parse(readFileSync(mainActiveSession, "utf8"));
      expect(content.origin).toBe("claude_code");
      expect(content.session_id).toBe("bbbbbbbb-cccc-4ddd-8eee-ffffffffffff");
    } finally {
      rmSync(repoParent, { recursive: true, force: true });
    }
  });

  it("writes active-session.json to the raw cwd when it is not a git checkout", async () => {
    // No `.git` present → canonicalRepoRoot degrades to the input path, so the
    // file lands directly under the detected repo root.
    const nonGitRoot = mkdtempSync(join(tmpdir(), "codogotchi-nogit-"));
    try {
      await runHook(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Edit",
          session_id: "cccccccc-dddd-4eee-8fff-000000000000",
          cwd: nonGitRoot,
        },
        { home, now: FIXED_NOW },
      );

      const activeSessionPath = join(nonGitRoot, ".soa", "active-session.json");
      expect(existsSync(activeSessionPath)).toBe(true);
      const content = JSON.parse(readFileSync(activeSessionPath, "utf8"));
      expect(content.session_id).toBe("cccccccc-dddd-4eee-8fff-000000000000");
    } finally {
      rmSync(nonGitRoot, { recursive: true, force: true });
    }
  });

  it("does not write active-session.json when the event carries no session id", async () => {
    const nonGitRoot = mkdtempSync(join(tmpdir(), "codogotchi-nosession-"));
    try {
      await runHook(
        {
          origin: "cursor",
          kind: "prompt_submit",
          cwd: nonGitRoot,
        },
        { home, now: FIXED_NOW },
      );

      const activeSessionPath = join(nonGitRoot, ".soa", "active-session.json");
      expect(existsSync(activeSessionPath)).toBe(false);
    } finally {
      rmSync(nonGitRoot, { recursive: true, force: true });
    }
  });

  it("does not write active-session.json when the session id is not UUID-shaped", async () => {
    const nonGitRoot = mkdtempSync(join(tmpdir(), "codogotchi-badsession-"));
    try {
      await runHook(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Edit",
          session_id: "ses-codex-keep",
          cwd: nonGitRoot,
        },
        { home, now: FIXED_NOW },
      );

      const activeSessionPath = join(nonGitRoot, ".soa", "active-session.json");
      expect(existsSync(activeSessionPath)).toBe(false);
    } finally {
      rmSync(nonGitRoot, { recursive: true, force: true });
    }
  });

  it("preserves a prior valid active-session.json when a later event has an unroutable session id", async () => {
    const nonGitRoot = mkdtempSync(join(tmpdir(), "codogotchi-preserve-"));
    try {
      await runHook(
        {
          origin: "claude_code",
          kind: "tool_use",
          name: "Edit",
          session_id: "dddddddd-eeee-4fff-8000-111111111111",
          cwd: nonGitRoot,
        },
        { home, now: FIXED_NOW },
      );

      await runHook(
        {
          origin: "codex",
          kind: "tool_use",
          name: "Edit",
          session_id: "ses-codex-keep",
          cwd: nonGitRoot,
        },
        { home, now: new Date(FIXED_NOW.getTime() + 1000) },
      );

      const activeSessionPath = join(nonGitRoot, ".soa", "active-session.json");
      const content = JSON.parse(readFileSync(activeSessionPath, "utf8"));
      expect(content.origin).toBe("claude_code");
      expect(content.session_id).toBe("dddddddd-eeee-4fff-8000-111111111111");
    } finally {
      rmSync(nonGitRoot, { recursive: true, force: true });
    }
  });
});
