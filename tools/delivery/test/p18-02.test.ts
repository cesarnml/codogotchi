import { describe, expect, it } from 'bun:test';

import { createOptions } from '../cli-runner';
import { formatStatus } from '../format';
import type { DeliveryState } from '../types';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import { syncStateFromScratch } from '../state';
import { restackTicket } from '../ticket-flow';

const baseConfig: ResolvedOrchestratorConfig = {
  defaultBranch: 'main',
  deliveryBaseBranch: 'main',
  closeoutBranch: 'main',
  planRoot: 'docs',
  runtime: 'bun',
  packageManager: 'bun',
  ticketBoundaryMode: 'gated',
  reviewPolicy: {
    subagentReview: 'skip_doc_only',
    prReview: 'disabled',
  },
};

const syncDeps = {
  cwd: '/tmp/repo',
  defaultBranch: 'main',
  deliveryBaseBranch: 'release-next',
  deriveBranchName: (definition: { id: string; slug: string }) =>
    `agents/${definition.id.toLowerCase()}-${definition.slug}`,
  deriveWorktreePath: (cwd: string, ticketId: string) =>
    `${cwd}/worktree-${ticketId.toLowerCase()}`,
};

const planOptions = createOptions({
  planPath: 'docs/product/delivery/phase-18/implementation-plan.md',
});

describe('P18.02 delivery base branch behavior', () => {
  it('uses deliveryBaseBranch, not defaultBranch, for the first ticket base', () => {
    const state = syncStateFromScratch(
      [
        {
          id: 'P18.01',
          title: 'First Ticket',
          slug: 'first-ticket',
          ticketFile:
            'docs/product/delivery/phase-18/ticket-01-first-ticket.md',
          type: 'feat',
        },
      ],
      planOptions,
      undefined,
      syncDeps,
    );

    expect(state.tickets[0]?.baseBranch).toBe('release-next');
  });

  it('rebases the first ticket onto origin/deliveryBaseBranch during restack', () => {
    const state: DeliveryState = {
      planKey: 'phase-18',
      planPath: 'docs/product/delivery/phase-18/implementation-plan.md',
      statePath: '.agents/delivery/phase-18/state.json',
      reviewsDirPath: 'docs/product/delivery/phase-18/reviews',
      handoffsDirPath: '.agents/delivery/phase-18/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      runPolicy: {
        ticketBoundaryMode: 'gated',
        subagentReview: 'skip_doc_only',
        prReview: 'disabled',
      },
      tickets: [
        {
          id: 'P18.01',
          title: 'Config schema and update migration',
          slug: 'config-schema-and-update-migration',
          ticketFile:
            'docs/product/delivery/phase-18/ticket-01-config-schema-and-update-migration.md',
          type: 'feat',
          branch: 'agents/p18-01-config-schema-and-update-migration',
          baseBranch: 'main',
          worktreePath: '/tmp/repo-p18-01',
          status: 'in_progress',
        },
      ],
    };
    const rebasedOnto: string[] = [];

    const next = restackTicket(state, '/tmp/repo-p18-01', undefined, {
      buildPullRequestBody: () => '',
      defaultBranch: 'main',
      deliveryBaseBranch: 'release-next',
      editPullRequest: () => {},
      ensureCleanWorktree: () => {},
      fetchOrigin: () => {},
      findOpenPullRequest: () => undefined,
      hasMergedPullRequestForBranch: () => false,
      readCurrentBranch: () =>
        'agents/p18-01-config-schema-and-update-migration',
      readMergeBase: () => '',
      rebaseOnto: () => {},
      rebaseOntoDefaultBranch: (_cwd, branch) => {
        rebasedOnto.push(branch);
      },
    });

    expect(rebasedOnto).toEqual(['release-next']);
    expect(next.tickets[0]?.baseBranch).toBe('release-next');
  });

  it('exposes configured delivery base branch in status output', () => {
    const state = syncStateFromScratch(
      [
        {
          id: 'P18.01',
          title: 'First Ticket',
          slug: 'first-ticket',
          ticketFile:
            'docs/product/delivery/phase-18/ticket-01-first-ticket.md',
          type: 'feat',
        },
      ],
      planOptions,
      undefined,
      syncDeps,
    );

    const status = formatStatus(state, {
      ...baseConfig,
      deliveryBaseBranch: 'release-next',
    });

    expect(status).toContain(
      'P18.01 | status=pending | branch=agents/p18.01-first-ticket | base=release-next',
    );
  });
});
