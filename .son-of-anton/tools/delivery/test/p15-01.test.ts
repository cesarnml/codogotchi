import { existsSync, mkdirSync, chmodSync, rmdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import { appendSoaEvent, buildSoaEventLine } from '../soa-event-feed';
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
    `p15-01-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(dir, { recursive: true });
  return dir;
}

describe('P15.01 — buildSoaEventLine', () => {
  it('returns an object with name, ts, and optional fields', () => {
    const line = buildSoaEventLine('ticket_started', {
      plan_key: 'phase-15',
      ticket_id: 'P15.01',
    });
    expect(line.name).toBe('ticket_started');
    expect(typeof line.ts).toBe('string');
    expect(Number.isFinite(Date.parse(line.ts))).toBe(true);
    expect(line.plan_key).toBe('phase-15');
    expect(line.ticket_id).toBe('P15.01');
  });

  it('omits optional fields when not provided', () => {
    const line = buildSoaEventLine('ticket_completed');
    expect(line.name).toBe('ticket_completed');
    expect(typeof line.ts).toBe('string');
    expect('plan_key' in line).toBe(false);
    expect('ticket_id' in line).toBe(false);
  });
});

describe('P15.01 — appendSoaEvent with gate enabled', () => {
  it('writes one NDJSON line to .soa/events.ndjson', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const event = buildSoaEventLine('ticket_started', {
      plan_key: 'phase-15',
      ticket_id: 'P15.01',
    });

    await appendSoaEvent(config, root, event);

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('ticket_started');
    expect(typeof parsed.ts).toBe('string');
    expect(Number.isFinite(Date.parse(parsed.ts))).toBe(true);
    expect(parsed.plan_key).toBe('phase-15');
    expect(parsed.ticket_id).toBe('P15.01');
  });

  it('appends two distinct lines when called twice', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    await appendSoaEvent(
      config,
      root,
      buildSoaEventLine('ticket_started', { ticket_id: 'P15.01' }),
    );
    await appendSoaEvent(
      config,
      root,
      buildSoaEventLine('ticket_completed', { ticket_id: 'P15.01' }),
    );

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(2);
    const first = JSON.parse(lines[0]!);
    const second = JSON.parse(lines[1]!);
    expect(first.name).toBe('ticket_started');
    expect(second.name).toBe('ticket_completed');
  });
});

describe('P15.01 — appendSoaEvent with gate disabled', () => {
  it('does not create .soa/ directory when codogotchi.enabled is false', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();

    await appendSoaEvent(config, root, buildSoaEventLine('ticket_started'));

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });
});

describe('P15.01 — appendSoaEvent error swallowing', () => {
  it('returns normally when projectRoot is non-writable', async () => {
    const parent = makeTmpDir();
    const root = join(parent, 'readonly-child');
    mkdirSync(root);
    chmodSync(root, 0o444);

    try {
      await expect(
        appendSoaEvent(
          enabledConfig(),
          root,
          buildSoaEventLine('ticket_started'),
        ),
      ).resolves.toBeUndefined();
    } finally {
      chmodSync(root, 0o755);
      rmdirSync(root);
    }
  });
});
