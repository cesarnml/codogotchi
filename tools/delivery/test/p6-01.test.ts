import { describe, expect, it } from 'bun:test';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const SCRIPT_PATH = resolve(import.meta.dir, '../../../scripts/soa-sync.sh');

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, 'utf8')) as Record<string, unknown>;
}

function initConsumerFixture(tmp: string): void {
  spawnSync('git', ['init'], { cwd: tmp });
  spawnSync('git', ['config', 'user.email', 'test@test.com'], { cwd: tmp });
  spawnSync('git', ['config', 'user.name', 'Test'], { cwd: tmp });
  // Mark as consumer repo (not source repo) by creating .son-of-anton
  mkdirSync(join(tmp, '.son-of-anton', '.agents', 'skills', 'dummy'), {
    recursive: true,
  });
}

function runSync(tmp: string): ReturnType<typeof spawnSync> {
  return spawnSync('bash', [SCRIPT_PATH], { cwd: tmp, encoding: 'utf8' });
}

describe('P6.01 soa-sync migration runner', () => {
  it('migrates .agents/delivery/*/reviews to docs/product/delivery/*/reviews and writes the target sync version', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-01-'));
    try {
      initConsumerFixture(tmp);

      // Create legacy reviews dir with a stub file and commit it.
      // Intentionally do NOT pre-create docs/product/delivery/phase-xx — the
      // script's mkdir -p must create it.
      mkdirSync(join(tmp, '.agents', 'delivery', 'phase-xx', 'reviews'), {
        recursive: true,
      });
      writeFileSync(
        join(tmp, '.agents', 'delivery', 'phase-xx', 'reviews', 'stub.md'),
        '# stub review',
      );
      spawnSync('git', ['add', '.'], { cwd: tmp });
      spawnSync('git', ['commit', '-m', 'initial: add legacy reviews'], {
        cwd: tmp,
      });

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      // .soa-sync-version must be written and contain the current target.
      const versionFile = join(tmp, '.soa-sync-version');
      expect(existsSync(versionFile)).toBe(true);
      expect(readFileSync(versionFile, 'utf8').trim()).toBe('2');

      // Stub file must be at new location
      expect(
        existsSync(
          join(
            tmp,
            'docs',
            'product',
            'delivery',
            'phase-xx',
            'reviews',
            'stub.md',
          ),
        ),
      ).toBe(true);

      // Old reviews dir must be gone
      expect(
        existsSync(join(tmp, '.agents', 'delivery', 'phase-xx', 'reviews')),
      ).toBe(false);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('is idempotent: second run produces no file mutations', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-01-idem-'));
    try {
      initConsumerFixture(tmp);

      mkdirSync(join(tmp, '.agents', 'delivery', 'phase-yy', 'reviews'), {
        recursive: true,
      });
      writeFileSync(
        join(tmp, '.agents', 'delivery', 'phase-yy', 'reviews', 'stub.md'),
        '# stub',
      );
      spawnSync('git', ['add', '.'], { cwd: tmp });
      spawnSync('git', ['commit', '-m', 'initial'], { cwd: tmp });

      // First run — performs migration
      expect(runSync(tmp).status).toBe(0);

      const migratedFile = join(
        tmp,
        'docs',
        'product',
        'delivery',
        'phase-yy',
        'reviews',
        'stub.md',
      );
      const mtimeBefore = statSync(migratedFile).mtimeMs;

      // Second run — must be a no-op
      expect(runSync(tmp).status).toBe(0);
      const mtimeAfter = statSync(migratedFile).mtimeMs;

      expect(mtimeAfter).toBe(mtimeBefore);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('skips git mv and writes the target sync version when .agents is a symlink', () => {
    // This is the topology every consumer repo has: soa-sync.sh itself creates
    // .agents as a symlink → .son-of-anton/.agents. Delivery files there are
    // git-ignored, so git mv would abort with "source directory is empty".
    const tmp = mkdtempSync(join(tmpdir(), 'p6-01-sym-'));
    try {
      initConsumerFixture(tmp);

      // Wire .agents as a symlink — same structure soa-sync.sh creates.
      symlinkSync('.son-of-anton/.agents', join(tmp, '.agents'));

      // Simulate untracked review artifacts that live under the symlinked path.
      mkdirSync(
        join(
          tmp,
          '.son-of-anton',
          '.agents',
          'delivery',
          'phase-aa',
          'reviews',
        ),
        { recursive: true },
      );
      writeFileSync(
        join(
          tmp,
          '.son-of-anton',
          '.agents',
          'delivery',
          'phase-aa',
          'reviews',
          'stub.json',
        ),
        '{}',
      );

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      // Version file must be written — migration is considered complete.
      const versionFile = join(tmp, '.soa-sync-version');
      expect(existsSync(versionFile)).toBe(true);
      expect(readFileSync(versionFile, 'utf8').trim()).toBe('2');

      // No docs/product/delivery path should have been created by the migration
      // (the guard returned early; nothing was moved).
      expect(
        existsSync(
          join(tmp, 'docs', 'product', 'delivery', 'phase-aa', 'reviews'),
        ),
      ).toBe(false);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('adds deliveryBaseBranch and closeoutBranch from an existing defaultBranch', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p18-01-master-'));
    try {
      initConsumerFixture(tmp);
      writeFileSync(join(tmp, '.soa-sync-version'), '1');
      writeFileSync(
        join(tmp, 'orchestrator.config.json'),
        JSON.stringify({ defaultBranch: 'master' }, null, 2),
      );

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      expect(readFileSync(join(tmp, '.soa-sync-version'), 'utf8').trim()).toBe(
        '2',
      );
      expect(readJson(join(tmp, 'orchestrator.config.json'))).toMatchObject({
        defaultBranch: 'master',
        deliveryBaseBranch: 'master',
        closeoutBranch: 'master',
      });
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('adds branch role fields as main when defaultBranch is missing', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p18-01-main-'));
    try {
      initConsumerFixture(tmp);
      writeFileSync(join(tmp, '.soa-sync-version'), '1');
      writeFileSync(
        join(tmp, 'orchestrator.config.json'),
        JSON.stringify({ planRoot: 'docs' }, null, 2),
      );

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      expect(readJson(join(tmp, 'orchestrator.config.json'))).toMatchObject({
        planRoot: 'docs',
        deliveryBaseBranch: 'main',
        closeoutBranch: 'main',
      });
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('preserves explicit branch role fields during migration', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p18-01-preserve-'));
    try {
      initConsumerFixture(tmp);
      writeFileSync(join(tmp, '.soa-sync-version'), '1');
      writeFileSync(
        join(tmp, 'orchestrator.config.json'),
        JSON.stringify(
          {
            defaultBranch: 'main',
            deliveryBaseBranch: 'develop',
            closeoutBranch: 'stable',
          },
          null,
          2,
        ),
      );

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      expect(readJson(join(tmp, 'orchestrator.config.json'))).toMatchObject({
        defaultBranch: 'main',
        deliveryBaseBranch: 'develop',
        closeoutBranch: 'stable',
      });
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });

  it('skips migration in source-repo mode (IS_SOURCE_REPO=true)', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'p6-01-src-'));
    try {
      initConsumerFixture(tmp);

      // Override to source-repo mode: create .agents/skills at root, no .son-of-anton
      rmSync(join(tmp, '.son-of-anton'), { force: true, recursive: true });
      mkdirSync(join(tmp, '.agents', 'skills', 'soa'), { recursive: true });
      writeFileSync(join(tmp, '.agents', 'skills', 'soa', 'SKILL.md'), '# soa');

      // Create legacy reviews — these must NOT be touched in source mode
      mkdirSync(join(tmp, '.agents', 'delivery', 'phase-zz', 'reviews'), {
        recursive: true,
      });
      writeFileSync(
        join(tmp, '.agents', 'delivery', 'phase-zz', 'reviews', 'stub.md'),
        '# stub',
      );
      spawnSync('git', ['add', '.'], { cwd: tmp });
      spawnSync('git', ['commit', '-m', 'initial'], { cwd: tmp });

      const result = runSync(tmp);
      expect(result.status).toBe(0);

      // .soa-sync-version must NOT be written in source mode
      expect(existsSync(join(tmp, '.soa-sync-version'))).toBe(false);

      // Legacy path must still exist (no migration ran)
      expect(
        existsSync(
          join(tmp, '.agents', 'delivery', 'phase-zz', 'reviews', 'stub.md'),
        ),
      ).toBe(true);
    } finally {
      rmSync(tmp, { force: true, recursive: true });
    }
  });
});
