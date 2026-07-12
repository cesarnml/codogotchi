import { describe, expect, it } from 'bun:test';

import type { ResolvedOrchestratorConfig } from '../runtime-config';
import {
  deriveRunPolicyFromConfig,
  normalizeDeliveryStateFromPersisted,
  normalizeRunPolicy,
} from '../state';
import type { DeliveryState, RunPolicy } from '../types';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: { subagentReview: 'skip_doc_only', prReview: 'skip_doc_only' },
};

const legacyRawState = {
  planKey: 'phase-06',
  planPath: 'docs/product/delivery/phase-06/implementation-plan.md',
  statePath: '.agents/delivery/phase-06/state.json',
  reviewsDirPath: '.agents/delivery/phase-06/reviews',
  handoffsDirPath: '.agents/delivery/phase-06/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [],
};

describe('P7.01 run-policy state model and migration', () => {
  describe('deriveRunPolicyFromConfig', () => {
    it('reflects ticketBoundaryMode from config', () => {
      const config: ResolvedOrchestratorConfig = {
        ...baseConfig,
        ticketBoundaryMode: 'gated',
      };
      const policy = deriveRunPolicyFromConfig(config);
      expect(policy.ticketBoundaryMode).toBe('gated');
    });

    it('reflects subagentReview and prReview from config reviewPolicy', () => {
      const config: ResolvedOrchestratorConfig = {
        ...baseConfig,
        reviewPolicy: { subagentReview: 'required', prReview: 'disabled' },
      };
      const policy = deriveRunPolicyFromConfig(config);
      expect(policy.subagentReview).toBe('required');
      expect(policy.prReview).toBe('disabled');
    });

    it('derives cook boundary mode from config', () => {
      const policy = deriveRunPolicyFromConfig(baseConfig);
      expect(policy.ticketBoundaryMode).toBe('cook');
    });
  });

  describe('normalizeRunPolicy', () => {
    it('derives runPolicy from config when absent in older state', () => {
      const state = legacyRawState as DeliveryState;
      const normalized = normalizeRunPolicy(state, baseConfig);
      expect(normalized.runPolicy).toBeDefined();
      expect(normalized.runPolicy!.ticketBoundaryMode).toBe('cook');
    });

    it('derives runPolicy from config when runPolicy is null in persisted state', () => {
      const state = {
        ...legacyRawState,
        runPolicy: null,
      } as unknown as DeliveryState;
      const normalized = normalizeRunPolicy(state, baseConfig);
      expect(normalized.runPolicy).toBeDefined();
      expect(normalized.runPolicy!.ticketBoundaryMode).toBe('cook');
    });

    it('leaves existing runPolicy unchanged when already present', () => {
      const existingPolicy: RunPolicy = {
        ticketBoundaryMode: 'gated',
        subagentReview: 'required',
        prReview: 'disabled',
      };
      const state = {
        ...legacyRawState,
        runPolicy: existingPolicy,
      } as DeliveryState;
      const normalized = normalizeRunPolicy(state, baseConfig);
      expect(normalized.runPolicy).toBe(existingPolicy);
    });
  });

  describe('RunPolicy shape survives round-trip', () => {
    it('RunPolicy survives JSON serialization', () => {
      const policy: RunPolicy = {
        ticketBoundaryMode: 'cook',
        subagentReview: 'skip_doc_only',
        prReview: 'skip_doc_only',
      };
      const serialized = JSON.parse(JSON.stringify(policy)) as RunPolicy;
      expect(serialized.ticketBoundaryMode).toBe('cook');
      expect(serialized.subagentReview).toBe('skip_doc_only');
      expect(serialized.prReview).toBe('skip_doc_only');
    });

    it('normalizeDeliveryStateFromPersisted preserves runPolicy when present', () => {
      const rawState = {
        ...legacyRawState,
        runPolicy: {
          ticketBoundaryMode: 'cook',
          subagentReview: 'skip_doc_only',
          prReview: 'skip_doc_only',
        },
      };
      const normalized = normalizeDeliveryStateFromPersisted(rawState);
      expect(normalized.runPolicy).toBeDefined();
      expect(normalized.runPolicy!.ticketBoundaryMode).toBe('cook');
    });
  });

  describe('backward compatibility', () => {
    it('normalizeDeliveryStateFromPersisted handles state without runPolicy without error', () => {
      const normalized = normalizeDeliveryStateFromPersisted(legacyRawState);
      expect(normalized.runPolicy).toBeUndefined();
    });
  });
});
