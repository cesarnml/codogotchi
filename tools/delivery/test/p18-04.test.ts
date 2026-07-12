import { describe, expect, it } from 'bun:test';

import {
  buildCloseoutBranchSyncCommands,
  buildCloseoutPrCloseComment,
  formatCloseoutSummary,
  formatCloseoutBranchGuardError,
} from '../closeout-stack';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import type { DeliveryState, TicketState } from '../types';

const baseConfig: ResolvedOrchestratorConfig = {
  closeoutBranch: 'staging',
  defaultBranch: 'main',
  deliveryBaseBranch: 'release-next',
  packageManager: 'bun',
  planRoot: 'docs',
  prReviewAgents: [],
  reviewPolicy: { prReview: 'disabled', subagentReview: 'skip_doc_only' },
  runtime: 'bun',
  ticketBoundaryMode: 'gated',
};

function createTicket(overrides: Partial<TicketState> = {}): TicketState {
  return {
    id: 'P18.04',
    title: 'Closeout target branch behavior',
    slug: 'closeout-target-branch-behavior',
    ticketFile:
      'docs/product/delivery/phase-18/ticket-04-closeout-target-branch-behavior.md',
    status: 'done',
    branch: 'agents/p18-04-closeout-target-branch-behavior',
    baseBranch: 'agents/p18-03-pr-metadata-and-state-repair-branch-roles',
    worktreePath: '/tmp/p18-04',
    prNumber: 95,
    prUrl: 'https://github.com/cesarnml/son-of-anton/pull/95',
    ...overrides,
  };
}

function createState(): DeliveryState {
  return {
    handoffsDirPath: '.agents/delivery/phase-18/handoffs',
    planKey: 'phase-18',
    planPath: 'docs/product/delivery/phase-18/implementation-plan.md',
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    reviewsDirPath: 'docs/product/delivery/phase-18/reviews',
    statePath: '.agents/delivery/phase-18/state.json',
    tickets: [createTicket()],
  };
}

describe('P18.04 closeout target branch behavior', () => {
  it('names closeoutBranch in the branch guard error', () => {
    expect(formatCloseoutBranchGuardError('staging', 'main')).toBe(
      'closeout-stack must run from the staging branch, but HEAD is on main.',
    );
  });

  it('builds closeout fetch, reset, and push commands from closeoutBranch', () => {
    expect(buildCloseoutBranchSyncCommands('staging')).toEqual({
      fetch: ['git', 'fetch', 'origin', 'staging'],
      resetHard: ['git', 'reset', '--hard', 'origin/staging'],
      push: ['git', 'push', 'origin', 'staging'],
    });
  });

  it('names closeoutBranch in PR close comments', () => {
    expect(buildCloseoutPrCloseComment('P18.04', 'staging', 'squash')).toBe(
      'Squash-merged to staging via closeout-stack (P18.04).',
    );

    expect(
      buildCloseoutPrCloseComment('P18.04', 'staging', 'cherry-pick'),
    ).toContain('Merged to staging via closeout-stack (P18.04).');
  });

  it('names closeoutBranch in closeout summaries', () => {
    const output = formatCloseoutSummary(
      {
        merged: [
          {
            landedVia: 'squash',
            prNumber: 95,
            ticketId: 'P18.04',
            url: 'https://github.com/cesarnml/son-of-anton/pull/95',
          },
        ],
        skippedMerged: [],
      },
      createState(),
      baseConfig,
    );

    expect(output).toContain('closeout_target=staging');
  });
});
