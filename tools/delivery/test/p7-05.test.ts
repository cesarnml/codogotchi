import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'bun:test';

import { getUsage } from '../cli';
import { formatRunPolicyDivergenceError } from '../state';
import type { RunPolicy } from '../types';

/**
 * P7.05 — Documentation and closeout verification.
 *
 * Two layers of coverage:
 * 1. Help-text assertions: `getUsage()` includes all Phase 07 flags.
 * 2. Doc-surface assertions: `start-here.md` and `delivery-orchestrator.md`
 *    document the runtime override flags shipped in Phase 07. These fail
 *    before doc updates and pass once the markdown is updated.
 */

const USAGE = getUsage('bun run deliver');

// Resolve docs relative to repo root (two dirs up from tools/delivery/test)
const REPO_ROOT = resolve(import.meta.dir, '../../..');
const START_HERE = readFileSync(
  resolve(REPO_ROOT, 'docs/template/overview/start-here.md'),
  'utf8',
);
const ORCHESTRATOR_DOC = readFileSync(
  resolve(REPO_ROOT, 'docs/template/delivery/delivery-orchestrator.md'),
  'utf8',
);

describe('P7.05 phase 07 shipped command surface — help text coverage', () => {
  it('getUsage includes --subagent-review-policy flag', () => {
    expect(USAGE).toContain('--subagent-review-policy');
  });

  it('getUsage includes --pr-review-policy flag', () => {
    expect(USAGE).toContain('--pr-review-policy');
  });

  it('getUsage includes --subagent flag', () => {
    expect(USAGE).toContain('--subagent');
  });

  it('getUsage includes --baseline flag', () => {
    expect(USAGE).toContain('--baseline');
  });

  it('getUsage includes the valid baseline values orchestrator and run-policy', () => {
    expect(USAGE).toContain('orchestrator');
    expect(USAGE).toContain('run-policy');
  });
});

describe('P7.05 doc-surface — start-here.md documents Phase 07 runtime overrides', () => {
  it('start-here.md mentions --boundary-mode runtime override flag', () => {
    expect(START_HERE).toContain('--boundary-mode');
  });

  it('start-here.md mentions --baseline flag for divergence recovery', () => {
    expect(START_HERE).toContain('--baseline');
  });
});

describe('P7.05 doc-surface — delivery-orchestrator.md documents Phase 07 flags', () => {
  it('delivery-orchestrator.md mentions --subagent-review-policy', () => {
    expect(ORCHESTRATOR_DOC).toContain('--subagent-review-policy');
  });

  it('delivery-orchestrator.md mentions --pr-review-policy', () => {
    expect(ORCHESTRATOR_DOC).toContain('--pr-review-policy');
  });

  it('delivery-orchestrator.md mentions --baseline', () => {
    expect(ORCHESTRATOR_DOC).toContain('--baseline');
  });

  it('docs use space-separated --baseline syntax (not --baseline=), matching the parser', () => {
    // The CLI parser only accepts "--baseline orchestrator", not "--baseline=orchestrator".
    // Docs must not teach operators a syntax that will silently fail.
    expect(START_HERE).not.toContain('--baseline=');
    expect(ORCHESTRATOR_DOC).not.toContain('--baseline=');
  });
});

describe('P7.05 divergence error message — runnable syntax', () => {
  const policy: RunPolicy = {
    ticketBoundaryMode: 'cook',
    subagentReview: 'skip_doc_only',
    prReview: 'skip_doc_only',
  };

  it('formatRunPolicyDivergenceError emits --baseline orchestrator (space-separated)', () => {
    const msg = formatRunPolicyDivergenceError(
      policy,
      { ...policy, ticketBoundaryMode: 'gated' },
      ['ticketBoundaryMode'],
      'bun run deliver --plan x.md post-verify',
    );
    // Must contain the parseable form, not the unsupported = form
    expect(msg).toContain('--baseline orchestrator');
    expect(msg).not.toContain('--baseline=orchestrator');
  });

  it('formatRunPolicyDivergenceError emits --baseline run-policy (space-separated)', () => {
    const msg = formatRunPolicyDivergenceError(
      policy,
      { ...policy, subagentReview: 'required' },
      ['subagentReview'],
      'bun run deliver --plan x.md post-verify',
    );
    expect(msg).toContain('--baseline run-policy');
    expect(msg).not.toContain('--baseline=run-policy');
  });
});
