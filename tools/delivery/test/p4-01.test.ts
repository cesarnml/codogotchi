import { describe, expect, it } from 'bun:test';

import {
  createWorkflowContractError,
  openPullRequest,
  runOptionalDependencyHook,
} from '../ticket-flow';
import type { DeliveryState } from '../types';

describe('P4.01 regressions', () => {
  it('keeps workflow identity stable even when operator prose changes', () => {
    const original = createWorkflowContractError(
      'workflow.open_pr.requires_post_verify',
      'Complete post-verify before opening a PR.',
    );
    const rewritten = createWorkflowContractError(
      'workflow.open_pr.requires_post_verify',
      'Finish the verification checkpoint before publishing the PR.',
    );

    expect(original).toMatchObject({
      code: 'workflow.open_pr.requires_post_verify',
    });
    expect(rewritten).toMatchObject({
      code: 'workflow.open_pr.requires_post_verify',
    });
    expect(original.message).not.toBe(rewritten.message);
  });

  it('treats omitted optional dependency hooks as no-ops', async () => {
    await expect(
      runOptionalDependencyHook<
        [state: { ticketId: string }, sourceWorktreePath: string]
      >(undefined, { ticketId: 'P4.01' }, '/tmp/p4_01'),
    ).resolves.toBeUndefined();
  });

  it('runs optional dependency hooks when they are supplied', async () => {
    const calls: Array<{ ticketId: string; sourceWorktreePath: string }> = [];

    await runOptionalDependencyHook(
      async (state: { ticketId: string }, sourceWorktreePath: string) => {
        calls.push({ ticketId: state.ticketId, sourceWorktreePath });
      },
      { ticketId: 'P4.01' },
      '/tmp/p4_01',
    );

    expect(calls).toEqual([
      { ticketId: 'P4.01', sourceWorktreePath: '/tmp/p4_01' },
    ]);
  });

  it('keeps the default open-pr path on the post-verify contract', () => {
    const state: DeliveryState = {
      planKey: 'phase-04',
      planPath: 'docs/product/delivery/phase-04/implementation-plan.md',
      statePath: '.agents/delivery/phase-04/state.json',
      reviewsDirPath: '.agents/delivery/phase-04/reviews',
      handoffsDirPath: '.agents/delivery/phase-04/handoffs',
      reviewPollIntervalMinutes: 6,
      reviewPollMaxWaitMinutes: 12,
      tickets: [
        {
          id: 'P4.01',
          title: 'Stable workflow contracts and DI safety',
          slug: 'stable-workflow-contracts-and-di-safety',
          ticketFile:
            'docs/product/delivery/phase-04/ticket-01-stable-workflow-contracts-di-safety.md',
          status: 'in_progress',
          branch: 'agents/p4-01-stable-workflow-contracts-and-di-safety',
          baseBranch: 'main',
          worktreePath: '/tmp/p4_01',
        },
      ],
    };

    try {
      openPullRequest(state, '/tmp/p4_01', undefined, {
        assertReviewerFacingMarkdown: () => {},
        buildPullRequestBody: () => 'body',
        buildPullRequestTitle: () => 'fix: example [P4.01]',
        createPullRequest: () => ({
          number: 1,
          url: 'https://example.test/pull/1',
        }),
        editPullRequest: () => {},
        ensureBranchPushed: () => {},
        findOpenPullRequest: () => undefined,
        subagentReviewPolicy: 'skip_doc_only',
      });
      throw new Error('Expected openPullRequest to throw.');
    } catch (error) {
      expect(error).toMatchObject({
        code: 'workflow.open_pr.requires_post_verify',
      });
      expect((error as Error).message).toContain('post-verify');
    }
  });
});
