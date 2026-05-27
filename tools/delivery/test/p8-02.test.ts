import { describe, it, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';

const repoRoot = join(import.meta.dirname, '../../..');

describe('P8.02 doc-surface — baseline run-policy execution semantics', () => {
  it('start-here.md describes --baseline run-policy as governing execution for the current invocation', () => {
    const content = readFileSync(
      join(repoRoot, 'docs/template/overview/start-here.md'),
      'utf8',
    );
    // --baseline run-policy must say it governs execution, not just keeps persisted state
    expect(content).toContain('governs execution');
  });

  it('delivery-orchestrator.md describes --baseline run-policy as governing execution for this invocation', () => {
    const content = readFileSync(
      join(repoRoot, 'docs/template/delivery/delivery-orchestrator.md'),
      'utf8',
    );
    // The run-policy baseline must be described as governing execution, not just state
    expect(content).toContain('governs execution');
  });
});
