import { describe, expect, it } from 'bun:test';

import type { DeliveryState, TicketState } from '../types';
import {
  getCloseoutTicketChain,
  isEmptyCherryPickFailure,
  orderCommitsForCherryPick,
  parseCloseoutStackArgs,
} from '../closeout-stack';

function createTicket(overrides: Partial<TicketState>): TicketState {
  return {
    id: 'P1.01',
    title: 'Example Ticket',
    slug: 'example-ticket',
    ticketFile: 'docs/product/delivery/phase-01/ticket-01-example.md',
    status: 'done',
    branch: 'agents/p1-01-example-ticket',
    baseBranch: 'main',
    worktreePath: '/tmp/p1-01',
    prNumber: 12,
    prUrl: 'https://github.com/example/repo/pull/12',
    ...overrides,
  };
}

function createState(tickets: TicketState[]): DeliveryState {
  return {
    planKey: 'phase-01',
    planPath: 'docs/product/delivery/phase-01/implementation-plan.md',
    statePath: '.agents/delivery/phase-01/state.json',
    reviewsDirPath: '.agents/delivery/phase-01/reviews',
    handoffsDirPath: '.agents/delivery/phase-01/handoffs',
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets,
  };
}

describe('closeout-stack', () => {
  describe('parseCloseoutStackArgs', () => {
    it('requires an explicit plan path', () => {
      expect(() => parseCloseoutStackArgs([])).toThrow(
        'Usage: bun run closeout-stack --plan <plan-path>',
      );
    });

    it('rejects a missing value for --plan', () => {
      expect(() => parseCloseoutStackArgs(['--plan'])).toThrow(
        'Usage: bun run closeout-stack --plan <plan-path>',
      );
    });

    it('parses the requested plan path', () => {
      expect(
        parseCloseoutStackArgs([
          '--plan',
          'docs/product/delivery/phase-07/implementation-plan.md',
        ]),
      ).toEqual({
        planPath: 'docs/product/delivery/phase-07/implementation-plan.md',
      });
    });
  });

  describe('getCloseoutTicketChain', () => {
    it('returns the full done ticket chain', () => {
      const state = createState([
        createTicket({ id: 'P1.01' }),
        createTicket({
          id: 'P1.02',
          branch: 'agents/p1-02-example-ticket',
          worktreePath: '/tmp/p1-02',
          prNumber: 13,
          prUrl: 'https://github.com/example/repo/pull/13',
        }),
      ]);

      expect(getCloseoutTicketChain(state).map((ticket) => ticket.id)).toEqual([
        'P1.01',
        'P1.02',
      ]);
    });

    it('rejects phases with incomplete tickets', () => {
      const state = createState([
        createTicket({ id: 'P1.01' }),
        createTicket({
          id: 'P1.02',
          status: 'reviewed',
          branch: 'agents/p1-02-example-ticket',
          worktreePath: '/tmp/p1-02',
          prNumber: 13,
          prUrl: 'https://github.com/example/repo/pull/13',
        }),
      ]);

      expect(() => getCloseoutTicketChain(state)).toThrow(
        'closeout-stack requires the full phase to be done first. Incomplete tickets: P1.02=reviewed',
      );
    });
  });

  describe('orderCommitsForCherryPick', () => {
    it('orders by authoredDate ascending, then oid', () => {
      expect(
        orderCommitsForCherryPick([
          { oid: 'bbbb', authoredDate: '2026-04-26T12:00:00Z' },
          { oid: 'aaaa', authoredDate: '2026-04-26T11:00:00Z' },
          { oid: 'cccc', authoredDate: '2026-04-26T11:00:00Z' },
        ]),
      ).toEqual(['aaaa', 'cccc', 'bbbb']);
    });

    it('treats missing authoredDate as empty string', () => {
      expect(
        orderCommitsForCherryPick([
          { oid: 'z' },
          { oid: 'a', authoredDate: '2026-01-01T00:00:00Z' },
        ]),
      ).toEqual(['z', 'a']);
    });
  });

  describe('isEmptyCherryPickFailure', () => {
    it('detects the standard git empty cherry-pick message', () => {
      expect(
        isEmptyCherryPickFailure(
          `The previous cherry-pick is now empty, possibly due to conflict resolution.
If you wish to commit it anyway, use:

    git commit --allow-empty`,
        ),
      ).toBe(true);
    });

    it('returns false for unrelated cherry-pick errors', () => {
      expect(
        isEmptyCherryPickFailure(
          'error: could not apply abc1234... patch failed at file.txt',
        ),
      ).toBe(false);
    });
  });
});
