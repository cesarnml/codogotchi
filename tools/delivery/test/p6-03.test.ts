import { describe, expect, it } from 'bun:test';
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const SCRIPT_PATH = resolve(import.meta.dir, '../../../scripts/soa-sync.sh');
const REPO_ROOT = resolve(import.meta.dir, '../../..');

function initConsumerFixture(tmp: string): void {
  spawnSync('git', ['init'], { cwd: tmp });
  spawnSync('git', ['config', 'user.email', 'test@test.com'], { cwd: tmp });
  spawnSync('git', ['config', 'user.name', 'Test'], { cwd: tmp });
  // Consumer-repo layout: .son-of-anton/ with skills and source files
  mkdirSync(join(tmp, '.son-of-anton', '.agents', 'skills', 'dummy'), {
    recursive: true,
  });
  cpSync(
    join(REPO_ROOT, 'AGENTS.soa.md'),
    join(tmp, '.son-of-anton', 'AGENTS.soa.md'),
  );
  cpSync(
    join(REPO_ROOT, 'CLAUDE.soa.md'),
    join(tmp, '.son-of-anton', 'CLAUDE.soa.md'),
  );
}

function runSync(tmp: string): ReturnType<typeof spawnSync> {
  return spawnSync('bash', [SCRIPT_PATH], { cwd: tmp, encoding: 'utf8' });
}

describe('P6.03 agent-rule injection', () => {
  it('Fixture A: injects <!-- soa:start/end --> block into AGENTS.md on fresh consumer', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-03-a-'));
    try {
      initConsumerFixture(tmp);
      const result = runSync(tmp);
      expect(result.status).toBe(0);

      const agentsMd = join(tmp, 'AGENTS.md');
      expect(existsSync(agentsMd)).toBe(true);
      const content = readFileSync(agentsMd, 'utf8');
      expect(content).toContain('<!-- soa:start -->');
      expect(content).toContain('<!-- soa:end -->');

      const blockContent = content
        .split('<!-- soa:start -->')[1]
        ?.split('<!-- soa:end -->')[0];
      expect(blockContent?.trim().length).toBeGreaterThan(0);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('Fixture A: injects <!-- soa:start/end --> block into CLAUDE.md on fresh consumer', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-03-a2-'));
    try {
      initConsumerFixture(tmp);
      const result = runSync(tmp);
      expect(result.status).toBe(0);

      const claudeMd = join(tmp, 'CLAUDE.md');
      expect(existsSync(claudeMd)).toBe(true);
      const content = readFileSync(claudeMd, 'utf8');
      expect(content).toContain('<!-- soa:start -->');
      expect(content).toContain('<!-- soa:end -->');
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('Fixture A: stdout contains lint-ignore warning', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-03-a3-'));
    try {
      initConsumerFixture(tmp);
      const result = runSync(tmp);
      expect(result.stdout).toContain('.son-of-anton');
      expect(result.stdout.toLowerCase()).toMatch(/lint|ignore|format/);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('Fixture B: second run is idempotent — AGENTS.md byte-for-byte identical', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-03-b-'));
    try {
      initConsumerFixture(tmp);
      runSync(tmp);

      const agentsMd = join(tmp, 'AGENTS.md');
      const before = readFileSync(agentsMd);
      runSync(tmp);
      const after = readFileSync(agentsMd);

      expect(Buffer.compare(before, after)).toBe(0);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('Fixture C: content outside markers is preserved when AGENTS.md already exists', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-03-c-'));
    try {
      initConsumerFixture(tmp);
      const existingContent = '# My Existing Rules\n\nCustom content here.\n';
      writeFileSync(join(tmp, 'AGENTS.md'), existingContent);

      runSync(tmp);

      const content = readFileSync(join(tmp, 'AGENTS.md'), 'utf8');
      expect(content).toContain('# My Existing Rules');
      expect(content).toContain('Custom content here.');
      expect(content).toContain('<!-- soa:start -->');
      expect(content).toContain('<!-- soa:end -->');
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });
});
