import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import type { ResolvedOrchestratorConfig } from '../config';
import { writeGateEvent } from '../codogotchi-gate';

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
    `p17-01-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(dir, { recursive: true });
  return dir;
}

describe('P17.01 — writeGateEvent produces gate.json with correct shape', () => {
  it('writes gate.json with the full { gate, since, expires_at, plan_key, ticket_id } shape', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      await writeGateEvent(enabledConfig(), {
        gate: 'ticket_started',
        planKey: 'phase-17',
        ticketId: 'P17.01',
      });

      const gateFile = join(home, 'gate.json');
      expect(existsSync(gateFile)).toBe(true);

      const raw = await readFile(gateFile, 'utf8');
      const parsed = JSON.parse(raw);
      expect(parsed.gate).toBe('ticket_started');
      expect(typeof parsed.since).toBe('string');
      expect(Number.isFinite(Date.parse(parsed.since))).toBe(true);
      expect(typeof parsed.expires_at).toBe('string');
      expect(Number.isFinite(Date.parse(parsed.expires_at))).toBe(true);
      expect(parsed.plan_key).toBe('phase-17');
      expect(parsed.ticket_id).toBe('P17.01');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('appends gate-transitions.log with the same emitted gate payload', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      await writeGateEvent(enabledConfig(), {
        gate: 'ticket_started',
        planKey: 'phase-17',
        ticketId: 'P17.01',
      });

      const raw = await readFile(join(home, 'gate-transitions.log'), 'utf8');
      const lines = raw.trim().split('\n');
      expect(lines).toHaveLength(1);

      const parsed = JSON.parse(lines[0]);
      expect(parsed.gate).toBe('ticket_started');
      expect(parsed.plan_key).toBe('phase-17');
      expect(parsed.ticket_id).toBe('P17.01');
      expect(typeof parsed.since).toBe('string');
      expect(typeof parsed.expires_at).toBe('string');
      expect(Number.isFinite(Date.parse(parsed.since))).toBe(true);
      expect(Number.isFinite(Date.parse(parsed.expires_at))).toBe(true);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('sets expires_at to since + 30_000 ms (flat 30-second TTL)', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      await writeGateEvent(enabledConfig(), {
        gate: 'open_pr',
        planKey: 'phase-17',
        ticketId: 'P17.01',
      });

      const raw = await readFile(join(home, 'gate.json'), 'utf8');
      const parsed = JSON.parse(raw);
      const since = Date.parse(parsed.since);
      const expiresAt = Date.parse(parsed.expires_at);
      expect(expiresAt - since).toBe(30_000);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.01 — writeGateEvent with codogotchi.enabled: false', () => {
  it('writes nothing and creates no directory when disabled', async () => {
    const home = makeTmpDir();
    // Point to a subdirectory that does not exist
    const targetHome = join(home, 'codogotchi-disabled');
    process.env['CODOGOTCHI_HOME'] = targetHome;
    try {
      await writeGateEvent(disabledConfig(), {
        gate: 'ticket_started',
        planKey: 'phase-17',
        ticketId: 'P17.01',
      });

      expect(existsSync(targetHome)).toBe(false);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.01 — writeGateEvent error swallowing', () => {
  it('does not throw when CODOGOTCHI_HOME is a path whose parent is a file', async () => {
    const tmp = makeTmpDir();
    // Create a file where the directory would be, making the target path unwritable
    const blockerFile = join(tmp, 'not-a-dir');
    writeFileSync(blockerFile, 'blocker');
    // Set CODOGOTCHI_HOME to a path inside the file (impossible to mkdir)
    process.env['CODOGOTCHI_HOME'] = join(blockerFile, 'subdir');
    try {
      await expect(
        writeGateEvent(enabledConfig(), {
          gate: 'ticket_started',
          planKey: 'phase-17',
          ticketId: 'P17.01',
        }),
      ).resolves.toBeUndefined();
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.01 — CODOGOTCHI_HOME edge cases', () => {
  it('falls back to ~/.codogotchi when CODOGOTCHI_HOME is empty string', async () => {
    // We test the || fallback by verifying empty string does NOT resolve to cwd/gate.json
    const savedHome = process.env['CODOGOTCHI_HOME'];
    process.env['CODOGOTCHI_HOME'] = '';
    try {
      // If the empty-string guard works, resolveCodogotchiHome() returns the homedir default,
      // not ''. We verify via the exported helper directly.
      const { resolveCodogotchiHome } = await import('../codogotchi-gate');
      const resolved = resolveCodogotchiHome();
      expect(resolved).not.toBe('');
      expect(resolved.length).toBeGreaterThan(0);
    } finally {
      if (savedHome === undefined) {
        delete process.env['CODOGOTCHI_HOME'];
      } else {
        process.env['CODOGOTCHI_HOME'] = savedHome;
      }
    }
  });

  it('writes gate.json when config.codogotchi is absent (absent = enabled)', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    const configWithoutCodogotchi: ResolvedOrchestratorConfig = {
      defaultBranch: 'main',
      planRoot: 'docs',
      runtime: 'bun',
      packageManager: 'bun',
      ticketBoundaryMode: 'cook',
      reviewPolicy: { subagentReview: 'skip_doc_only', prReview: 'disabled' },
      // codogotchi field intentionally absent
    };
    try {
      await writeGateEvent(configWithoutCodogotchi, {
        gate: 'ticket_started',
        planKey: 'phase-17',
        ticketId: 'P17.01',
      });
      expect(existsSync(join(home, 'gate.json'))).toBe(true);
      expect(existsSync(join(home, 'gate-transitions.log'))).toBe(true);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});
