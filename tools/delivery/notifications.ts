import { resolve } from 'node:path';

import { buildReviewPollCheckMinutes } from './review';
import { readReviewArtifacts } from './review-artifacts';
import type {
  DeliveryNotificationEvent,
  DeliveryState,
  ReviewResult,
  StandaloneAiReviewResult,
  TicketState,
} from './types';

export type DeliveryNotifier =
  | {
      kind: 'noop';
      enabled: false;
    }
  | {
      kind: 'telegram';
      enabled: true;
      botToken: string;
      chatId: string;
    };

type NotificationPayload = {
  entities?: Array<{
    length: number;
    offset: number;
    type: 'text_link';
    url: string;
  }>;
  text: string;
};

const TELEGRAM_SEND_TIMEOUT_MS = 10_000;

function findTicketById(
  state: DeliveryState,
  ticketId?: string,
): TicketState | undefined {
  return ticketId
    ? state.tickets.find((ticket) => ticket.id === ticketId)
    : (state.tickets.find((ticket) => ticket.status === 'in_review') ??
        state.tickets.find(
          (ticket) => ticket.status === 'operator_input_needed',
        ));
}

function buildTicketStartedEvent(
  state: DeliveryState,
  ticket: Pick<TicketState, 'id' | 'title' | 'branch'>,
): DeliveryNotificationEvent {
  return {
    kind: 'ticket_started',
    planKey: state.planKey,
    ticketId: ticket.id,
    ticketTitle: ticket.title,
    branch: ticket.branch,
  };
}

function buildPrOpenedEvent(
  state: DeliveryState,
  ticket: Pick<TicketState, 'id' | 'title' | 'branch' | 'prUrl'>,
): DeliveryNotificationEvent | undefined {
  if (!ticket.prUrl) {
    return undefined;
  }

  return {
    kind: 'pr_opened',
    planKey: state.planKey,
    ticketId: ticket.id,
    ticketTitle: ticket.title,
    branch: ticket.branch,
    prUrl: ticket.prUrl,
  };
}

function buildReviewRecordedEvent(
  state: DeliveryState,
  ticket: Pick<
    TicketState,
    | 'id'
    | 'title'
    | 'branch'
    | 'prUrl'
    | 'reviewArtifactJsonPath'
    | 'reviewArtifactPath'
    | 'reviewFetchArtifactPath'
    | 'reviewNote'
    | 'reviewOutcome'
    | 'reviewTriageArtifactPath'
    | 'status'
  >,
): DeliveryNotificationEvent | undefined {
  const artifacts = readReviewArtifacts({
    fetchArtifactPath: ticket.reviewFetchArtifactPath
      ? resolve(ticket.reviewFetchArtifactPath)
      : ticket.reviewArtifactPath
        ? resolve(ticket.reviewArtifactPath)
        : undefined,
    triageArtifactPath: ticket.reviewTriageArtifactPath
      ? resolve(ticket.reviewTriageArtifactPath)
      : ticket.reviewArtifactJsonPath
        ? resolve(ticket.reviewArtifactJsonPath)
        : undefined,
  });
  const outcome: ReviewResult | undefined =
    artifacts.triage?.outcome ??
    ticket.reviewOutcome ??
    (ticket.status === 'needs_patch'
      ? 'needs_patch'
      : ticket.status === 'operator_input_needed'
        ? 'operator_input_needed'
        : undefined);

  if (!outcome) {
    return undefined;
  }

  return {
    kind: 'review_recorded',
    planKey: state.planKey,
    ticketId: ticket.id,
    ticketTitle: ticket.title,
    branch: ticket.branch,
    outcome,
    note: artifacts.triage?.note ?? ticket.reviewNote,
    prUrl: ticket.prUrl,
  };
}

function buildTicketCompletedEvent(
  state: DeliveryState,
  ticket: Pick<TicketState, 'id' | 'title' | 'branch' | 'prUrl'>,
): DeliveryNotificationEvent {
  return {
    kind: 'ticket_completed',
    planKey: state.planKey,
    ticketId: ticket.id,
    ticketTitle: ticket.title,
    branch: ticket.branch,
    prUrl: ticket.prUrl,
  };
}

function buildReviewWindowReadyEvent(
  state: DeliveryState,
  ticket: Pick<TicketState, 'id' | 'title' | 'branch' | 'prUrl' | 'prOpenedAt'>,
): DeliveryNotificationEvent | undefined {
  if (!ticket.prUrl || !ticket.prOpenedAt) {
    return undefined;
  }

  const openedAt = Date.parse(ticket.prOpenedAt);

  if (Number.isNaN(openedAt)) {
    return undefined;
  }

  return {
    kind: 'review_window_ready',
    planKey: state.planKey,
    ticketId: ticket.id,
    ticketTitle: ticket.title,
    branch: ticket.branch,
    prUrl: ticket.prUrl,
    reviewPollIntervalMinutes: state.reviewPollIntervalMinutes,
    reviewPollMaxWaitMinutes: state.reviewPollMaxWaitMinutes,
    firstCheckAt: new Date(
      openedAt + state.reviewPollIntervalMinutes * 60_000,
    ).toISOString(),
    finalCheckAt: new Date(
      openedAt + state.reviewPollMaxWaitMinutes * 60_000,
    ).toISOString(),
  };
}

export function buildRunBlockedEvent(
  planKey: string | undefined,
  command: string | undefined,
  reason: string,
): DeliveryNotificationEvent {
  return {
    kind: 'run_blocked',
    planKey,
    command,
    reason,
  };
}

export function buildStandaloneReviewRecordedEvent(
  result: StandaloneAiReviewResult,
): DeliveryNotificationEvent {
  return {
    kind: 'standalone_review_recorded',
    prNumber: result.prNumber,
    prUrl: result.prUrl,
    outcome: result.outcome,
    note: result.note,
  };
}

export function resolveNotifier(): DeliveryNotifier {
  const botToken = process.env.TELEGRAM_BOT_TOKEN?.trim();
  const chatId = process.env.TELEGRAM_CHAT_ID?.trim();

  if (!botToken || !chatId) {
    return {
      kind: 'noop',
      enabled: false,
    };
  }

  return {
    kind: 'telegram',
    enabled: true,
    botToken,
    chatId,
  };
}

export function eventsForStartCommand(
  state: DeliveryState,
  ticketId?: string,
): DeliveryNotificationEvent[] {
  const ticket = ticketId
    ? state.tickets.find((candidate) => candidate.id === ticketId)
    : state.tickets.find((candidate) => candidate.status === 'in_progress');

  return ticket ? [buildTicketStartedEvent(state, ticket)] : [];
}

export function eventsForOpenPrCommand(
  state: DeliveryState,
  ticketId?: string,
): DeliveryNotificationEvent[] {
  const ticket = findTicketById(state, ticketId);

  if (!ticket) {
    return [];
  }

  return [
    buildPrOpenedEvent(state, ticket),
    buildReviewWindowReadyEvent(state, ticket),
  ].filter((event): event is DeliveryNotificationEvent => event !== undefined);
}

export function eventsForRecordReviewCommand(
  state: DeliveryState,
  ticketId: string,
): DeliveryNotificationEvent[] {
  const ticket = state.tickets.find((candidate) => candidate.id === ticketId);

  return ticket
    ? [buildReviewRecordedEvent(state, ticket)].filter(
        (event): event is DeliveryNotificationEvent => event !== undefined,
      )
    : [];
}

export function eventsForReconcileLateReviewCommand(
  state: DeliveryState,
  ticketId: string,
): DeliveryNotificationEvent[] {
  const ticket = state.tickets.find((candidate) => candidate.id === ticketId);

  if (!ticket || ticket.status !== 'done') {
    return [];
  }

  return [buildReviewRecordedEvent(state, ticket)].filter(
    (event): event is DeliveryNotificationEvent => event !== undefined,
  );
}

export function eventsForPollReviewCommand(
  state: DeliveryState,
  ticketId?: string,
): DeliveryNotificationEvent[] {
  const ticket = ticketId
    ? state.tickets.find((candidate) => candidate.id === ticketId)
    : (state.tickets.find((candidate) => candidate.status === 'in_review') ??
      state.tickets.find(
        (candidate) =>
          candidate.status === 'needs_patch' ||
          candidate.status === 'operator_input_needed',
      ) ??
      state.tickets.find(
        (candidate) =>
          candidate.status === 'reviewed' &&
          candidate.reviewOutcome !== undefined,
      ));

  if (
    !ticket ||
    (ticket.status !== 'reviewed' &&
      ticket.status !== 'needs_patch' &&
      ticket.status !== 'operator_input_needed') ||
    (!ticket.reviewOutcome &&
      ticket.status !== 'needs_patch' &&
      ticket.status !== 'operator_input_needed')
  ) {
    return [];
  }

  return [buildReviewRecordedEvent(state, ticket)].filter(
    (event): event is DeliveryNotificationEvent => event !== undefined,
  );
}

export function eventsForAdvanceCommand(
  previousState: DeliveryState,
  nextState: DeliveryState,
): DeliveryNotificationEvent[] {
  const events: DeliveryNotificationEvent[] = [];

  for (const previousTicket of previousState.tickets) {
    const nextTicket = nextState.tickets.find(
      (candidate) => candidate.id === previousTicket.id,
    );

    if (previousTicket.status !== 'done' && nextTicket?.status === 'done') {
      events.push(buildTicketCompletedEvent(nextState, nextTicket));
    }

    if (
      previousTicket.status !== 'in_progress' &&
      nextTicket?.status === 'in_progress'
    ) {
      events.push(buildTicketStartedEvent(nextState, nextTicket));
    }
  }

  return events;
}

export function formatReviewWindowMessage(
  state: DeliveryState,
  ticketId?: string,
): string {
  const ticket = findTicketById(state, ticketId);

  if (!ticket?.prUrl || !ticket.prOpenedAt) {
    return '';
  }

  if (ticket.docOnly) {
    return [
      'AI Review Window',
      '- doc_only=true',
      '- external AI review window skipped for docs-only PRs',
      '- run `poll-review` to record `skipped` immediately and continue',
    ].join('\n');
  }

  const openedAt = Date.parse(ticket.prOpenedAt);

  if (Number.isNaN(openedAt)) {
    return '';
  }

  const checks = buildReviewPollCheckMinutes(
    state.reviewPollIntervalMinutes,
    state.reviewPollMaxWaitMinutes,
  );
  const firstCheckAt = new Date(
    openedAt + state.reviewPollIntervalMinutes * 60_000,
  ).toISOString();
  const finalCheckAt = new Date(
    openedAt + state.reviewPollMaxWaitMinutes * 60_000,
  ).toISOString();

  return [
    'AI Review Window',
    `- polling cadence: every ${state.reviewPollIntervalMinutes} minutes up to ${state.reviewPollMaxWaitMinutes} minutes`,
    `- checks at: ${checks.join(', ')} minutes after PR open`,
    `- first check at: ${firstCheckAt}`,
    `- final check at: ${finalCheckAt}`,
    '- if no actionable `pr-review` findings are captured by the final applicable check, the orchestrator records `clean` and continues',
  ].join('\n');
}

export function formatNotificationMessage(
  _cwd: string,
  event: DeliveryNotificationEvent,
): string {
  const header = 'Son of Anton';
  const standaloneHeader = `Son of Anton PR #${
    event.kind === 'standalone_review_started' ||
    event.kind === 'standalone_review_recorded'
      ? event.prNumber
      : ''
  }`.trim();

  switch (event.kind) {
    case 'ticket_started':
      return [
        header,
        `${event.ticketId} underway for ${event.planKey}.`,
        event.ticketTitle,
        `Branch: ${event.branch}`,
      ].join('\n');
    case 'pr_opened':
      return [
        header,
        `${event.ticketId} is up for review in ${event.planKey}.`,
        event.ticketTitle,
        `Branch: ${event.branch}`,
        `PR: ${event.prUrl}`,
      ].join('\n');
    case 'review_window_ready':
      return [
        header,
        `Review window is open for ${event.ticketId}.`,
        event.ticketTitle,
        `Branch: ${event.branch}`,
        `PR: ${event.prUrl}`,
        `Cadence: every ${event.reviewPollIntervalMinutes} minutes up to ${event.reviewPollMaxWaitMinutes} minutes`,
        `First check: ${event.firstCheckAt}`,
        `Final check: ${event.finalCheckAt}`,
      ].join('\n');
    case 'review_recorded':
      return [
        header,
        `${event.ticketId} review triaged.`,
        event.ticketTitle,
        `Branch: ${event.branch}`,
        `Outcome: ${event.outcome}`,
        event.note ? `Note: ${event.note}` : undefined,
        event.prUrl ? `PR: ${event.prUrl}` : undefined,
      ]
        .filter((line): line is string => line !== undefined)
        .join('\n');
    case 'ticket_completed':
      return [
        header,
        `${event.ticketId} cleared.`,
        event.ticketTitle,
        `Branch: ${event.branch}`,
        event.prUrl ? `PR: ${event.prUrl}` : undefined,
      ]
        .filter((line): line is string => line !== undefined)
        .join('\n');
    case 'standalone_review_started':
      return [standaloneHeader, 'AI review started.'].join('\n');
    case 'standalone_review_recorded':
      return [
        standaloneHeader,
        'AI review complete.',
        `Outcome: ${event.outcome}`,
        event.note ? `Note: ${event.note}` : undefined,
      ]
        .filter((line): line is string => line !== undefined)
        .join('\n');
    case 'run_blocked':
      return [
        header,
        `Stopped${event.planKey ? ` in ${event.planKey}` : ''}.`,
        event.command ? `Command: ${event.command}` : undefined,
        `Reason: ${event.reason}`,
      ]
        .filter((line): line is string => line !== undefined)
        .join('\n');
  }
}

function buildNotificationPayload(
  cwd: string,
  event: DeliveryNotificationEvent,
): NotificationPayload {
  const text = formatNotificationMessage(cwd, event);

  if (
    event.kind !== 'standalone_review_started' &&
    event.kind !== 'standalone_review_recorded'
  ) {
    return { text };
  }

  const linkLabel = `PR #${event.prNumber}`;
  const offset = text.indexOf(linkLabel);

  if (offset === -1) {
    return { text };
  }

  return {
    text,
    entities: [
      {
        type: 'text_link',
        offset,
        length: linkLabel.length,
        url: event.prUrl,
      },
    ],
  };
}

async function sendTelegramMessage(
  botToken: string,
  chatId: string,
  payload: NotificationPayload,
): Promise<void> {
  const response = await fetch(
    `https://api.telegram.org/bot${botToken}/sendMessage`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        chat_id: chatId,
        text: payload.text,
        entities: payload.entities,
        disable_web_page_preview: true,
      }),
      signal: AbortSignal.timeout(TELEGRAM_SEND_TIMEOUT_MS),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Telegram sendMessage failed with ${response.status}: ${await response.text()}`,
    );
  }
}

function formatError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}

export async function notifyBestEffort(
  notifier: DeliveryNotifier,
  cwd: string,
  event: DeliveryNotificationEvent,
): Promise<string | undefined> {
  if (!notifier.enabled) {
    return undefined;
  }

  try {
    await sendTelegramMessage(notifier.botToken, notifier.chatId, {
      ...buildNotificationPayload(cwd, event),
    });
    return undefined;
  } catch (error) {
    return `Notification warning: ${formatError(error)}`;
  }
}

export async function emitNotificationWarnings(
  notifier: DeliveryNotifier,
  cwd: string,
  events: DeliveryNotificationEvent[],
): Promise<void> {
  for (const event of events) {
    const warning = await notifyBestEffort(notifier, cwd, event);

    if (warning) {
      console.warn(warning);
    }
  }
}
