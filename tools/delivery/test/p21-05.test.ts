import { describe, expect, it } from 'bun:test';

import {
  eventsForSubagentReviewCommand,
  formatNotificationMessage,
  notifyBestEffort,
  resolveNotifier,
} from '../notifications';
import type { DeliveryState, TicketState } from '../types';

function makeTicket(id: string, overrides?: Partial<TicketState>): TicketState {
  return {
    id,
    title: `Ticket ${id}`,
    slug: id.toLowerCase(),
    redPolicy: 'required',
    ticketFile: `docs/delivery/ticket-${id}.md`,
    status: 'subagent_review_complete',
    branch: `agents/${id}`,
    baseBranch: 'main',
    worktreePath: '/tmp/fake',
    ...overrides,
  };
}

function makeState(planKey: string, tickets: TicketState[]): DeliveryState {
  return {
    planKey,
    planPath: `docs/product/delivery/${planKey}/implementation-plan.md`,
    statePath: `.agents/delivery/${planKey}/state.json`,
    reviewsDirPath: `docs/product/delivery/${planKey}/reviews`,
    handoffsDirPath: `.agents/delivery/${planKey}/handoffs`,
    reviewPollIntervalMinutes: 6,
    reviewPollMaxWaitMinutes: 12,
    tickets,
  };
}

const PLAN_KEY = 'phase-21';
const TICKET_ID = 'P21.05';

describe('P21.05 — eventsForSubagentReviewCommand', () => {
  it('produces exactly one subagent_review_recorded event with the recorded outcome and count', () => {
    const ticket = makeTicket(TICKET_ID);
    const state = makeState(PLAN_KEY, [ticket]);

    const events = eventsForSubagentReviewCommand(
      state,
      TICKET_ID,
      'completed_with_findings',
      { findingsCount: 3 },
    );

    expect(events).toHaveLength(1);
    expect(events[0]).toEqual({
      kind: 'subagent_review_recorded',
      planKey: PLAN_KEY,
      ticketId: TICKET_ID,
      ticketTitle: `Ticket ${TICKET_ID}`,
      branch: `agents/${TICKET_ID}`,
      outcome: 'completed_with_findings',
      findingsCount: 3,
    });
  });

  it('produces no event when the ticket is not found', () => {
    const state = makeState(PLAN_KEY, [makeTicket(TICKET_ID)]);

    const events = eventsForSubagentReviewCommand(state, 'P21.99', 'clean');

    expect(events).toEqual([]);
  });

  it('carries terminatedReason for a skipped outcome', () => {
    const ticket = makeTicket(TICKET_ID);
    const state = makeState(PLAN_KEY, [ticket]);

    const events = eventsForSubagentReviewCommand(state, TICKET_ID, 'skipped', {
      terminatedReason: 'runner_unavailable',
    });

    expect(events[0]).toMatchObject({
      outcome: 'skipped',
      terminatedReason: 'runner_unavailable',
    });
  });
});

describe('P21.05 — payload text differs meaningfully by outcome', () => {
  it('clean: states it passed with no actionable findings', () => {
    const text = formatNotificationMessage('/tmp/test_project', {
      kind: 'subagent_review_recorded',
      planKey: PLAN_KEY,
      ticketId: TICKET_ID,
      ticketTitle: 'Subagent-review outcome notification',
      branch: `agents/${TICKET_ID}`,
      outcome: 'clean',
    });
    expect(text).toContain('passed, no actionable findings');
  });

  it('completed_with_findings: states what was found, never "passed"', () => {
    const text = formatNotificationMessage('/tmp/test_project', {
      kind: 'subagent_review_recorded',
      planKey: PLAN_KEY,
      ticketId: TICKET_ID,
      ticketTitle: 'Subagent-review outcome notification',
      branch: `agents/${TICKET_ID}`,
      outcome: 'completed_with_findings',
      findingsCount: 4,
    });
    expect(text).toContain('found 4 actionable finding(s)');
    expect(text).not.toContain('passed');
  });

  it('skipped: states the termination reason', () => {
    const text = formatNotificationMessage('/tmp/test_project', {
      kind: 'subagent_review_recorded',
      planKey: PLAN_KEY,
      ticketId: TICKET_ID,
      ticketTitle: 'Subagent-review outcome notification',
      branch: `agents/${TICKET_ID}`,
      outcome: 'skipped',
      terminatedReason: 'runner_unavailable',
    });
    expect(text).toContain('skipped (runner_unavailable)');
  });
});

describe('P21.05 — notifier failure stays best-effort', () => {
  it('keeps notification failures best-effort', async () => {
    const originalToken = process.env.TELEGRAM_BOT_TOKEN;
    const originalChatId = process.env.TELEGRAM_CHAT_ID;
    const originalWebhook = process.env.DISCORD_WEBHOOK_URL;
    const originalFetch = globalThis.fetch;

    process.env.TELEGRAM_BOT_TOKEN = 'bot-token';
    process.env.TELEGRAM_CHAT_ID = 'chat-id';
    delete process.env.DISCORD_WEBHOOK_URL;
    globalThis.fetch = (async () =>
      new Response('nope', { status: 500 })) as unknown as typeof fetch;

    const warning = await notifyBestEffort(
      resolveNotifier(),
      '/tmp/test_project',
      {
        kind: 'subagent_review_recorded',
        planKey: PLAN_KEY,
        ticketId: TICKET_ID,
        ticketTitle: 'Subagent-review outcome notification',
        branch: `agents/${TICKET_ID}`,
        outcome: 'clean',
      },
    );

    expect(warning).toContain('Notification warning:');
    expect(warning).toContain('Telegram sendMessage failed with 500');

    if (originalToken === undefined) delete process.env.TELEGRAM_BOT_TOKEN;
    else process.env.TELEGRAM_BOT_TOKEN = originalToken;
    if (originalChatId === undefined) delete process.env.TELEGRAM_CHAT_ID;
    else process.env.TELEGRAM_CHAT_ID = originalChatId;
    if (originalWebhook === undefined) delete process.env.DISCORD_WEBHOOK_URL;
    else process.env.DISCORD_WEBHOOK_URL = originalWebhook;
    globalThis.fetch = originalFetch;
  });
});
