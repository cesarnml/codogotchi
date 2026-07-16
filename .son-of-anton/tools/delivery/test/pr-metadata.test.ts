import { describe, expect, it } from 'bun:test';

import { buildPullRequestBody } from '../pr-metadata';
import type { DeliveryState } from '../types';

function makeTwoTicketState(
  overrides: Partial<DeliveryState> = {},
): DeliveryState {
  return {
    planKey: 'phase-99',
    planPath: 'docs/product/delivery/phase-99/implementation-plan.md',
    statePath: '.agents/delivery/phase-99/state.json',
    reviewsDirPath: 'docs/product/delivery/phase-99/reviews',
    handoffsDirPath: '.agents/delivery/phase-99/handoffs',
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets: [
      {
        id: 'P99.01',
        title: 'First Ticket',
        slug: 'first-ticket',
        ticketFile: 'docs/product/delivery/phase-99/ticket-01-first-ticket.md',
        type: 'feat',
        scope: 'delivery',
        redPolicy: 'required',
        status: 'subagent_review_complete',
        branch: 'agents/p99-01-first-ticket',
        baseBranch: 'main',
        worktreePath: '/tmp/repo-p99-01',
      },
      {
        id: 'P99.02',
        title: 'Second Ticket',
        slug: 'second-ticket',
        ticketFile: 'docs/product/delivery/phase-99/ticket-02-second-ticket.md',
        type: 'feat',
        scope: 'delivery',
        redPolicy: 'required',
        status: 'subagent_review_complete',
        branch: 'agents/p99-02-second-ticket',
        baseBranch: 'agents/p99-01-first-ticket',
        worktreePath: '/tmp/repo-p99-02',
      },
    ],
    ...overrides,
  } satisfies DeliveryState;
}

describe('buildPullRequestBody — origin issue closing line', () => {
  it('does not add a Closes line when no originIssueNumber is set', () => {
    const state = makeTwoTicketState();
    const body = buildPullRequestBody(state, state.tickets[1]!);
    expect(body).not.toContain('Closes #');
  });

  it('does not add a Closes line to a non-final ticket even with originIssueNumber set', () => {
    const state = makeTwoTicketState({ originIssueNumber: 76 });
    const body = buildPullRequestBody(state, state.tickets[0]!);
    expect(body).not.toContain('Closes #');
  });

  it('adds a Closes line to the final ticket in the phase when originIssueNumber is set', () => {
    const state = makeTwoTicketState({ originIssueNumber: 76 });
    const body = buildPullRequestBody(state, state.tickets[1]!);
    expect(body).toContain('- Closes #76');
  });
});
