import { describe, expect, it } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const REPO_ROOT = resolve(import.meta.dir, '../../..');

describe('P19.03 quality-control skill dispatch docs', () => {
  const qualityControlSkillPath = join(
    REPO_ROOT,
    '.agents',
    'skills',
    'quality-control',
    'SKILL.md',
  );
  const soaSkillPath = join(REPO_ROOT, '.agents', 'skills', 'soa', 'SKILL.md');

  it('defines the quality-control skill metadata and verified-fix sequence', () => {
    expect(existsSync(qualityControlSkillPath)).toBe(true);

    const content = readFileSync(qualityControlSkillPath, 'utf8');
    expect(content).toContain('name: soa-quality-control');
    expect(content).toContain('/soa quality-control phase-NN: <description>');
    expect(content).toContain('/soa qc phase-NN: <description>');
    expect(content).toContain('human verification');
    expect(content).toContain('commit');
    expect(content).toContain('docs/product/review-gaps/ledger.jsonl');
    expect(content).toContain('record-review-gap');
    expect(content).toContain('promotion-queue.md');
  });

  it('documents quality-control and qc dispatch through the SoA entrypoint', () => {
    const content = readFileSync(soaSkillPath, 'utf8');
    expect(content).toContain('quality control');
    expect(content).toContain('quality-control');
    expect(content).toContain('qc');
    expect(content).toContain('/soa quality-control phase-NN: <description>');
    expect(content).toContain('/soa qc phase-NN: <description>');
    expect(content).toContain('phase-NN');
  });
});
