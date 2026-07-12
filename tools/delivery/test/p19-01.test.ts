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
  mkdirSync(join(tmp, '.son-of-anton', '.agents', 'skills', 'dummy'), {
    recursive: true,
  });
  mkdirSync(join(tmp, '.son-of-anton', 'docs', 'template'), {
    recursive: true,
  });
  cpSync(
    join(REPO_ROOT, 'docs', 'template', 'review-gaps'),
    join(tmp, '.son-of-anton', 'docs', 'template', 'review-gaps'),
    { recursive: true },
  );
}

function runSync(tmp: string): ReturnType<typeof spawnSync> {
  return spawnSync('bash', [SCRIPT_PATH], { cwd: tmp, encoding: 'utf8' });
}

describe('P19.01 review-gap scaffold sync', () => {
  it('creates the review-gap scaffold in a fresh consumer repo', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p19-01-fresh-'));
    try {
      initConsumerFixture(tmp);

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      const scaffoldDir = join(tmp, 'docs', 'product', 'review-gaps');
      expect(existsSync(join(scaffoldDir, 'README.md'))).toBe(true);
      expect(existsSync(join(scaffoldDir, 'ledger.jsonl'))).toBe(true);
      expect(existsSync(join(scaffoldDir, 'promotion-queue.md'))).toBe(true);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('preserves existing consumer review-gap files on rerun', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p19-01-preserve-'));
    try {
      initConsumerFixture(tmp);
      const scaffoldDir = join(tmp, 'docs', 'product', 'review-gaps');
      mkdirSync(scaffoldDir, { recursive: true });
      const existingLedger = '{"custom":true}\n';
      writeFileSync(join(scaffoldDir, 'ledger.jsonl'), existingLedger);

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      expect(readFileSync(join(scaffoldDir, 'ledger.jsonl'), 'utf8')).toBe(
        existingLedger,
      );
      expect(existsSync(join(scaffoldDir, 'README.md'))).toBe(true);
      expect(existsSync(join(scaffoldDir, 'promotion-queue.md'))).toBe(true);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });
});
