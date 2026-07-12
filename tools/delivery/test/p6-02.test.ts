import { describe, expect, it } from 'bun:test';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const REPO_ROOT = resolve(import.meta.dir, '../../..');

describe('P6.02 retrospective location migration', () => {
  const retroDir = join(REPO_ROOT, 'docs', 'product', 'retrospectives');
  const notesPublicDir = join(REPO_ROOT, 'notes', 'public');
  const skillPath = join(
    REPO_ROOT,
    '.agents',
    'skills',
    'write-retrospective',
    'SKILL.md',
  );

  it('docs/product/retrospectives/ exists', () => {
    expect(existsSync(retroDir)).toBe(true);
  });

  it('phase-03 retro is in docs/product/retrospectives/', () => {
    expect(
      existsSync(
        join(retroDir, 'phase-03-orchestrator-ergonomics-retrospective.md'),
      ),
    ).toBe(true);
  });

  it('phase-04 retro is in docs/product/retrospectives/', () => {
    expect(
      existsSync(
        join(
          retroDir,
          'phase-04-orchestrator-contract-stability-retrospective.md',
        ),
      ),
    ).toBe(true);
  });

  it('phase-05 retro is in docs/product/retrospectives/', () => {
    expect(
      existsSync(
        join(
          retroDir,
          'phase-05-subagent-review-clarity-and-pr-scope-propagation-retrospective.md',
        ),
      ),
    ).toBe(true);
  });

  it('notes/public/ contains no retrospective artifacts', () => {
    const retroFiles = readdirSync(notesPublicDir).filter((f) =>
      f.endsWith('-retrospective.md'),
    );
    expect(retroFiles).toEqual([]);
  });

  it('soa-write-retrospective skill does not reference notes/public/', () => {
    const content = readFileSync(skillPath, 'utf8');
    expect(content).not.toContain('notes/public/');
  });
});
