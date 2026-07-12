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
    }
  | {
      kind: 'discord';
      enabled: true;
      webhookUrl: string;
    };

export type NotificationPayload = {
  entities?: Array<{
    length: number;
    offset: number;
    type: 'text_link';
    url: string;
  }>;
  text: string;
};

const TELEGRAM_SEND_TIMEOUT_MS = 10_000;
const DISCORD_SEND_TIMEOUT_MS = 10_000;
// Discord webhook message flag: SUPPRESS_EMBEDS. Mirrors Telegram's
// `disable_web_page_preview` so bare URLs don't expand into preview cards.
const DISCORD_SUPPRESS_EMBEDS_FLAG = 4;

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

  // Telegram wins when fully configured: this preserves the prior behavior for
  // anyone already on Telegram who also sets a Discord webhook to experiment.
  if (botToken && chatId) {
    return {
      kind: 'telegram',
      enabled: true,
      botToken,
      chatId,
    };
  }

  const webhookUrl = process.env.DISCORD_WEBHOOK_URL?.trim();

  if (webhookUrl) {
    return {
      kind: 'discord',
      enabled: true,
      webhookUrl,
    };
  }

  return {
    kind: 'noop',
    enabled: false,
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

// Discord renders the webhook `content` field as Markdown, whereas Telegram
// renders our payload as plain text. Escape Markdown so notes, titles, and
// branches read literally on Discord, matching Telegram. The intentional
// `[label](url)` link spans are emitted unescaped by buildDiscordContent.
//
// Brackets and parens are escaped too: free-form text (e.g. a review note
// derived from lower-trust AI review comments) containing `[text](url)` must
// not render as a live masked link in the channel.
//
// Inline markers can fire anywhere on a line; block markers (headings,
// blockquotes, bullet/ordered lists, subtext) only fire at the start of a
// line, so escaping is applied per line.
const DISCORD_INLINE_METACHARACTERS = /[\\`*_~|[\]()]/g;
const DISCORD_LINE_START_MARKER = /^(\s*)(-#|#{1,3}|>{1,3}|[-+]|\d+\.)(?=\s)/;

function escapeDiscordMarkdown(text: string): string {
  return text
    .split('\n')
    .map((line) =>
      line
        .replace(DISCORD_INLINE_METACHARACTERS, (char) => `\\${char}`)
        .replace(DISCORD_LINE_START_MARKER, (_match, leading, marker) =>
          // Ordered lists trigger on `N.`; escape the dot. Every other block
          // marker is neutralized by escaping its leading symbol.
          /^\d/.test(marker)
            ? `${leading}${marker.replace('.', '\\.')}`
            : `${leading}\\${marker}`,
        ),
    )
    .join('\n');
}

export function buildDiscordContent(payload: NotificationPayload): string {
  const { entities, text } = payload;

  if (!entities || entities.length === 0) {
    return escapeDiscordMarkdown(text);
  }

  // The payload's `text_link` entities are platform-neutral position data
  // (offset/length/url). Build the content left-to-right: escape the prose
  // between links and splice each in-range entity into a real Markdown link.
  // Out-of-range or overlapping entities are skipped so a malformed offset
  // degrades to plain (escaped) text instead of emitting a broken link.
  const ordered = [...entities]
    .filter(
      (entity) =>
        entity.offset >= 0 && entity.offset + entity.length <= text.length,
    )
    .sort((a, b) => a.offset - b.offset);

  let content = '';
  let cursor = 0;

  for (const entity of ordered) {
    if (entity.offset < cursor) {
      continue;
    }

    content += escapeDiscordMarkdown(text.slice(cursor, entity.offset));
    content += `[${text.slice(entity.offset, entity.offset + entity.length)}](${entity.url})`;
    cursor = entity.offset + entity.length;
  }

  content += escapeDiscordMarkdown(text.slice(cursor));

  return content;
}

async function sendDiscordMessage(
  webhookUrl: string,
  payload: NotificationPayload,
): Promise<void> {
  const response = await fetch(webhookUrl, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      content: buildDiscordContent(payload),
      flags: DISCORD_SUPPRESS_EMBEDS_FLAG,
      // Milestone messages are informational: never parse mentions so a
      // free-form ticket title or review note cannot accidentally ping a role
      // or @everyone.
      allowed_mentions: { parse: [] },
    }),
    signal: AbortSignal.timeout(DISCORD_SEND_TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(
      `Discord webhook failed with ${response.status}: ${await response.text()}`,
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
    const payload = buildNotificationPayload(cwd, event);

    if (notifier.kind === 'telegram') {
      await sendTelegramMessage(notifier.botToken, notifier.chatId, payload);
    } else {
      await sendDiscordMessage(notifier.webhookUrl, payload);
    }

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
