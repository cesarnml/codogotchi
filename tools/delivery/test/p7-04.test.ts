import { describe, expect, it } from 'bun:test';

import { formatRunPolicy, formatStatus } from '../format';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import type { DeliveryState, RunPolicy } from '../types';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: {
    subagentReview: 'skip_doc_only',
    prReview: 'skip_doc_only',
  },
};

const baseState: DeliveryState = {
  planKey: 'phase-07',
  planPath: 'docs/product/delivery/phase-07/implementation-plan.md',
  statePath: '.agents/delivery/phase-07/state.json',
  reviewsDirPath: 'docs/product/delivery/phase-07/reviews',
  handoffsDirPath: '.agents/delivery/phase-07/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [],
};

const samTypePolicy: RunPolicy = {
  ticketBoundaryMode: 'cook',
  subagentReview: 'skip_doc_only',
  prReview: 'skip_doc_only',
};

const overridePolicy: RunPolicy = {
  ticketBoundaryMode: 'gated',
  subagentReview: 'required',
  prReview: 'disabled',
};

// ─── formatRunPolicy ─────────────────────────────────────────────────────────

describe('P7.04 run-policy observability', () => {
  describe('formatRunPolicy', () => {
    it('renders ticketBoundaryMode', () => {
      expect(formatRunPolicy(samTypePolicy)).toContain('boundary_mode=cook');
    });

    it('renders subagentReview', () => {
      expect(formatRunPolicy(samTypePolicy)).toContain(
        'subagentReview:skip_doc_only',
      );
    });

    it('renders prReview', () => {
      expect(formatRunPolicy(samTypePolicy)).toContain(
        'prReview:skip_doc_only',
      );
    });

    it('renders all three fields in a single string', () => {
      const out = formatRunPolicy(overridePolicy);
      expect(out).toContain('boundary_mode=gated');
      expect(out).toContain('subagentReview:required');
      expect(out).toContain('prReview:disabled');
      expect(out).not.toContain('reviewSubagent');
    });
  });

  // ─── formatStatus — run_policy line ──────────────────────────────────────────

  describe('formatStatus — run_policy line', () => {
    it('includes run_policy line when state.runPolicy is set', () => {
      const state: DeliveryState = {
        ...baseState,
        runPolicy: samTypePolicy,
      };
      const out = formatStatus(state, baseConfig);
      expect(out).toContain('run_policy=');
    });

    it('omits run_policy line when state.runPolicy is absent', () => {
      const state: DeliveryState = { ...baseState };
      const out = formatStatus(state, baseConfig);
      expect(out).not.toContain('run_policy=');
    });

    it('shows the persisted boundary_mode from runPolicy, not just from config', () => {
      const state: DeliveryState = {
        ...baseState,
        runPolicy: overridePolicy, // boundary_mode=gated
      };
      // Config still says cook — the run_policy line should reflect the persisted value
      const out = formatStatus(state, baseConfig);
      expect(out).toContain('run_policy=');
      // The run_policy block must show gated (persisted), not cook (config)
      const runPolicyLine = out
        .split('\n')
        .find((l) => l.startsWith('run_policy='));
      expect(runPolicyLine).toContain('gated');
    });

    it('shows subagentReview value in the run_policy line', () => {
      const state: DeliveryState = {
        ...baseState,
        runPolicy: overridePolicy,
      };
      const out = formatStatus(state, baseConfig);
      const runPolicyLine = out
        .split('\n')
        .find((l) => l.startsWith('run_policy='));
      expect(runPolicyLine).toContain('subagentReview:required');
    });

    it('labels the run_policy line as [persisted] to distinguish it from config lines', () => {
      const state: DeliveryState = {
        ...baseState,
        runPolicy: samTypePolicy,
      };
      const out = formatStatus(state, baseConfig);
      const runPolicyLine = out
        .split('\n')
        .find((l) => l.startsWith('run_policy='));
      expect(runPolicyLine).toContain('[persisted]');
    });

    it('omits run_policy line when state.runPolicy is explicitly undefined', () => {
      const state: DeliveryState = { ...baseState, runPolicy: undefined };
      const out = formatStatus(state, baseConfig);
      expect(out).not.toContain('run_policy=');
    });
  });

  // ─── formatRunPolicy — additional edge cases ──────────────────────────────────

  describe('formatRunPolicy — additional edge cases', () => {
    it('renders required subagentReview', () => {
      const policy: RunPolicy = {
        ...samTypePolicy,
        subagentReview: 'required',
      };
      expect(formatRunPolicy(policy)).toContain('subagentReview:required');
    });

    it('renders disabled prReview', () => {
      const policy: RunPolicy = { ...samTypePolicy, prReview: 'disabled' };
      expect(formatRunPolicy(policy)).toContain('prReview:disabled');
    });
  });
});
