import { existsSync, mkdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import { emitSubagentInvoked } from '../soa-event-feed';
import type { ResolvedOrchestratorConfig } from '../config';

function enabledConfig(): ResolvedOrchestratorConfig {
  return {
    defaultBranch: 'main',
    planRoot: 'docs',
    runtime: 'bun',
    packageManager: 'bun',
    ticketBoundaryMode: 'cook',
    reviewPolicy: { subagentReview: 'skip_doc_only', prReview: 'disabled' },
    codogotchi: { enabled: true },
  };
}

function disabledConfig(): ResolvedOrchestratorConfig {
  return { ...enabledConfig(), codogotchi: { enabled: false } };
}

function makeTmpDir(): string {
  const dir = join(
    tmpdir(),
    `p15-05-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(dir, { recursive: true });
  return dir;
}

const PLAN_KEY = 'phase-15';
const TICKET_ID = 'P15.05';

describe('P15.05 — emitSubagentInvoked (gate enabled)', () => {
  it('writes one subagent_invoked event with correct fields for claude-cli', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'claude-cli');

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('subagent_invoked');
    expect(parsed.plan_key).toBe(PLAN_KEY);
    expect(parsed.ticket_id).toBe(TICKET_ID);
    expect(parsed.payload).toEqual({ runnerKind: 'claude-cli' });
  });

  it('writes one subagent_invoked event with correct fields for codex-cli', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'codex-cli');

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('subagent_invoked');
    expect(parsed.payload).toEqual({ runnerKind: 'codex-cli' });
  });

  it('appends two subagent_invoked events for a fallback scenario (preferred + fallback runner)', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    // Simulate: preferred runner (codex-cli) unavailable → fallback to claude-cli
    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'codex-cli');
    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'claude-cli');

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(2);

    const first = JSON.parse(lines[0]!);
    expect(first.name).toBe('subagent_invoked');
    expect(first.payload).toEqual({ runnerKind: 'codex-cli' });

    const second = JSON.parse(lines[1]!);
    expect(second.name).toBe('subagent_invoked');
    expect(second.payload).toEqual({ runnerKind: 'claude-cli' });
  });

  it('includes ts field in each event', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'claude-cli');

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const parsed = JSON.parse(content.trim());
    expect(typeof parsed.ts).toBe('string');
    expect(new Date(parsed.ts).getTime()).not.toBeNaN();
  });
});

describe('P15.05 — emitSubagentInvoked (gate disabled)', () => {
  it('does not create .soa/events.ndjson when codogotchi.enabled is false', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();

    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'claude-cli');

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });

  it('suppresses both attempts in a fallback scenario when gate is disabled', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();

    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'codex-cli');
    await emitSubagentInvoked(config, root, PLAN_KEY, TICKET_ID, 'claude-cli');

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });
});
