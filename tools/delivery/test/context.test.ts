import { describe, expect, it } from 'bun:test';

import {
  createDeliveryOrchestratorContext,
  type DeliveryOrchestratorContext,
} from '../context';
import type { ResolvedOrchestratorConfig } from '../runtime-config';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'cook',
  reviewPolicy: {
    subagentReview: 'skip_doc_only',
    prReview: 'disabled',
  },
};

describe('delivery orchestrator context', () => {
  it('carries only resolved config, invocation, and platform adapters', () => {
    const context = createDeliveryOrchestratorContext(baseConfig);

    expect(Object.keys(context).sort()).toEqual([
      'config',
      'invocation',
      'platform',
    ]);
    expect(context.config).toBe(baseConfig);
    expect(context.invocation).toBe('bun run deliver');
    expect(context.platform.runProcessResult).toBeFunction();
  });

  it('derives npm invocation with the script argument separator', () => {
    const context = createDeliveryOrchestratorContext({
      ...baseConfig,
      packageManager: 'npm',
    });

    expect(context.invocation).toBe('npm run deliver --');
  });

  it('exposes the canonical context type', () => {
    const context: DeliveryOrchestratorContext =
      createDeliveryOrchestratorContext(baseConfig);

    expect(context.config.packageManager).toBe('bun');
  });
});
