import { describe, expect, it } from 'bun:test';

import { applyRunPolicyToConfig } from '../state';
import type { RunPolicy } from '../types';
import type { ResolvedOrchestratorConfig } from '../config';

/**
 * P8.01 — applyRunPolicyToConfig merges runPolicy fields over config.
 *
 * Tests the pure helper that is the logical inverse of deriveRunPolicyFromConfig.
 * Given a config and a persisted runPolicy that diverges on the three bounded
 * fields, applyRunPolicyToConfig must return a new config where every field is
 * taken from the runPolicy, not the original config.
 */

const BASE_CONFIG: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'gated',
  reviewPolicy: {
    subagentReview: 'required',
    prReview: 'required',
  },
};

const PERSISTED_RUN_POLICY: RunPolicy = {
  ticketBoundaryMode: 'cook',
  subagentReview: 'skip_doc_only',
  prReview: 'skip_doc_only',
};

describe('P8.01 applyRunPolicyToConfig', () => {
  it('overrides ticketBoundaryMode from runPolicy', () => {
    const result = applyRunPolicyToConfig(BASE_CONFIG, PERSISTED_RUN_POLICY);
    expect(result.ticketBoundaryMode).toBe('cook');
  });

  it('overrides reviewPolicy.subagentReview from runPolicy', () => {
    const result = applyRunPolicyToConfig(BASE_CONFIG, PERSISTED_RUN_POLICY);
    expect(result.reviewPolicy.subagentReview).toBe('skip_doc_only');
  });

  it('overrides reviewPolicy.prReview from runPolicy', () => {
    const result = applyRunPolicyToConfig(BASE_CONFIG, PERSISTED_RUN_POLICY);
    expect(result.reviewPolicy.prReview).toBe('skip_doc_only');
  });

  it('preserves unchanged config fields not governed by runPolicy', () => {
    const result = applyRunPolicyToConfig(BASE_CONFIG, PERSISTED_RUN_POLICY);
    expect(result.defaultBranch).toBe('main');
    expect(result.planRoot).toBe('docs');
    expect(result.runtime).toBe('bun');
    expect(result.packageManager).toBe('bun');
  });
});
