import { describe, expect, it } from 'bun:test';

import { createOptions } from '../cli-runner';
import { buildPullRequestBody } from '../pr-metadata';
import { syncStateFromExisting } from '../state';
import { openPullRequest } from '../ticket-flow';
import type { DeliveryState, TicketDefinition } from '../types';

const planOptions = createOptions({
  planPath: 'docs/product/delivery/phase-18/implementation-plan.md',
});

const ticketDefinitions: TicketDefinition[] = [
  {
    id: 'P18.01',
    title: 'First Ticket',
    slug: 'first-ticket',
    ticketFile: 'docs/product/delivery/phase-18/ticket-01-first-ticket.md',
    type: 'feat',
    scope: 'delivery',
    redPolicy: 'required',
  },
];

function makeState(overrides: Partial<DeliveryState['tickets'][number]> = {}) {
  return {
    planKey: 'phase-18',
    planPath: 'docs/product/delivery/phase-18/implementation-plan.md',
    statePath: '.agents/delivery/phase-18/state.json',
    reviewsDirPath: 'docs/product/delivery/phase-18/reviews',
    handoffsDirPath: '.agents/delivery/phase-18/handoffs',
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets: [
      {
        ...ticketDefinitions[0]!,
        status: 'subagent_review_complete',
        branch: 'agents/p18-01-first-ticket',
        baseBranch: 'release-next',
        worktreePath: '/tmp/repo-p18-01',
        ...overrides,
      },
    ],
  } satisfies DeliveryState;
}

describe('P18.03 PR metadata and state repair branch roles', () => {
  it('links ticket files to repo-primary defaultBranch while showing the stacked base branch', () => {
    const state = makeState();
    const body = buildPullRequestBody(state, state.tickets[0]!, {
      githubRepo: {
        defaultBranch: 'main',
        name: 'son-of-anton',
        owner: 'cesarnml',
      },
    });

    expect(body).toContain(
      'https://github.com/cesarnml/son-of-anton/blob/main/docs/product/delivery/phase-18/ticket-01-first-ticket.md',
    );
    expect(body).toContain('- stacked base branch: `release-next`');
    expect(body).not.toContain('/blob/release-next/');
  });

  it('refreshes an existing PR against the ticket base branch, not repo-primary defaultBranch', () => {
    const state = makeState();
    const editCalls: Array<{
      prNumber: number;
      options: { base?: string; body?: string; title?: string };
    }> = [];

    const next = openPullRequest(state, '/tmp/repo', undefined, {
      assertReviewerFacingMarkdown: () => {},
      buildPullRequestBody,
      buildPullRequestTitle: () => 'feat(delivery): first ticket [P18.01]',
      createPullRequest: () => {
        throw new Error('Expected existing PR refresh.');
      },
      editPullRequest: (_cwd, prNumber, options) => {
        editCalls.push({ prNumber, options });
      },
      ensureBranchPushed: () => {},
      findOpenPullRequest: () => ({
        branch: 'agents/p18-01-first-ticket',
        number: 42,
        url: 'https://github.com/cesarnml/son-of-anton/pull/42',
      }),
      resolveGitHubRepo: () => ({
        defaultBranch: 'main',
        name: 'son-of-anton',
        owner: 'cesarnml',
      }),
      subagentReviewPolicy: 'skip_doc_only',
    });

    expect(editCalls).toEqual([
      {
        prNumber: 42,
        options: expect.objectContaining({
          base: 'release-next',
          body: expect.stringContaining(
            '- stacked base branch: `release-next`',
          ),
          title: 'feat(delivery): first ticket [P18.01]',
        }),
      },
    ]);
    expect(editCalls[0]?.options.body).toContain('/blob/main/');
    expect(editCalls[0]?.options.body).not.toContain('/blob/release-next/');
    expect(next.tickets[0]?.prNumber).toBe(42);
  });

  it('repairs a stale first-ticket base to deliveryBaseBranch instead of defaultBranch', () => {
    const repaired = syncStateFromExisting(
      makeState({ baseBranch: 'main', status: 'pending' }),
      ticketDefinitions,
      planOptions,
      undefined,
      {
        cwd: '/tmp/repo',
        deliveryBaseBranch: 'release-next',
        deriveBranchName: (definition) =>
          `agents/${definition.id.toLowerCase()}-${definition.slug}`,
        deriveWorktreePath: (cwd, ticketId) =>
          `${cwd}/worktree-${ticketId.toLowerCase()}`,
      },
    );

    expect(repaired.tickets[0]?.baseBranch).toBe('release-next');
  });
});
