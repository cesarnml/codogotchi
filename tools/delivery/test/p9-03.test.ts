import { describe, expect, it } from 'bun:test';

import { recordPostVerify } from '../cli-runner';
import type { ResolvedOrchestratorConfig } from '../runtime-config';
import type { DeliveryState } from '../types';

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
  planKey: 'phase-09',
  planPath: 'docs/product/delivery/phase-09/implementation-plan.md',
  statePath: '.agents/delivery/phase-09/state.json',
  reviewsDirPath: '.agents/delivery/phase-09/reviews',
  handoffsDirPath: '.agents/delivery/phase-09/handoffs',
  reviewPollIntervalMinutes: 6,
  reviewPollMaxWaitMinutes: 12,
  tickets: [
    {
      id: 'P9.03',
      title: 'Exit Hygiene & Template Fixes',
      slug: 'exit-hygiene-template-fixes',
      ticketFile: 'docs/product/delivery/phase-09/ticket-03-exit-hygiene.md',
      status: 'red_complete',
      branch: 'agents/p9-03-exit-hygiene-template-fixes',
      baseBranch: 'agents/p9-02-tdd-gate-hardening',
      worktreePath: '/tmp/p9_03',
      redCommitSha: 'red123',
    },
  ],
};

describe('P9.03 exit hygiene', () => {
  it('warns when post-verify records with uncommitted changes present', async () => {
    const warnings: string[] = [];

    const nextState = await recordPostVerify(
      baseState,
      'P9.03',
      'clean',
      baseConfig,
      {
        getWorkingTreeStatus: () => 'M src/foo.ts\n?? notes.txt',
        hasUncommittedChanges: () => true,
        isLocalBranchDocOnly: () => false,
        warn: (message) => warnings.push(message),
      },
    );

    expect(nextState.tickets[0]?.status).toBe('verified');
    expect(warnings).toEqual([
      [
        'Warning: working tree has uncommitted changes.',
        'Confirm these are intentional before recording post-verify clean.',
        'Uncommitted files:',
        '  M src/foo.ts',
        '  ?? notes.txt',
      ].join('\n'),
    ]);
  });

  it('keeps post-verify non-blocking when dirty-worktree inspection throws', async () => {
    const nextState = await recordPostVerify(
      baseState,
      'P9.03',
      'clean',
      baseConfig,
      {
        hasUncommittedChanges: () => {
          throw new Error('git status failed');
        },
        isLocalBranchDocOnly: () => false,
      },
    );

    expect(nextState.tickets[0]?.status).toBe('verified');
  });
});
