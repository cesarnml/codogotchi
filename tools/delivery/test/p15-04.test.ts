import { existsSync, mkdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import {
  eventsForPollReviewCommand,
  eventsForReconcileLateReviewCommand,
  eventsForRecordReviewCommand,
} from '../notifications';
import { maybeEmitReviewCleanRecorded } from '../soa-event-feed';
import type { ResolvedOrchestratorConfig } from '../config';
import type { DeliveryState, TicketState } from '../types';

function enabledConfig(): ResolvedOrchestratorConfig {
  return {
    defaultBranch: 'main',
    planRoot: 'docs',
    runtime: 'bun',
    packageManager: 'bun',
    ticketBoundaryMode: 'cook',
    reviewPolicy: { subagentReview: 'skip_doc_only', prReview: 'disabled' },
    codogotchi: { enabled: true },
  };
}

function disabledConfig(): ResolvedOrchestratorConfig {
  return { ...enabledConfig(), codogotchi: { enabled: false } };
}

function makeTmpDir(): string {
  const dir = join(
    tmpdir(),
    `p15-04-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(dir, { recursive: true });
  return dir;
}

function makeTicket(id: string, overrides?: Partial<TicketState>): TicketState {
  return {
    id,
    title: `Ticket ${id}`,
    slug: id.toLowerCase(),
    redPolicy: 'required',
    ticketFile: `docs/delivery/ticket-${id}.md`,
    status: 'in_review',
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

const PLAN_KEY = 'phase-15';
const TICKET_ID = 'P15.04';

// ─── record-review path ───────────────────────────────────────────────────────

describe('P15.04 — record-review path (gate enabled)', () => {
  it('emits review_clean_recorded when outcome is clean', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const ticket = makeTicket(TICKET_ID, {
      status: 'reviewed',
      reviewOutcome: 'clean',
    });
    const state = makeState(PLAN_KEY, [ticket]);
    const events = eventsForRecordReviewCommand(state, TICKET_ID);

    await maybeEmitReviewCleanRecorded(events, config, root);

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('review_clean_recorded');
    expect(parsed.plan_key).toBe(PLAN_KEY);
    expect(parsed.ticket_id).toBe(TICKET_ID);
  });

  it('does not emit review_clean_recorded when outcome is needs_patch', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const ticket = makeTicket(TICKET_ID, {
      status: 'needs_patch',
      reviewOutcome: 'needs_patch',
    });
    const state = makeState(PLAN_KEY, [ticket]);
    const events = eventsForRecordReviewCommand(state, TICKET_ID);

    await maybeEmitReviewCleanRecorded(events, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });
});

// ─── poll-review path ─────────────────────────────────────────────────────────

describe('P15.04 — poll-review path (gate enabled)', () => {
  it('emits review_clean_recorded when poll resolves to clean', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const ticket = makeTicket(TICKET_ID, {
      status: 'reviewed',
      reviewOutcome: 'clean',
    });
    const state = makeState(PLAN_KEY, [ticket]);
    const events = eventsForPollReviewCommand(state, TICKET_ID);

    await maybeEmitReviewCleanRecorded(events, config, root);

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('review_clean_recorded');
    expect(parsed.plan_key).toBe(PLAN_KEY);
    expect(parsed.ticket_id).toBe(TICKET_ID);
  });
});

// ─── triage-ticket (reconcile-late-review) path ───────────────────────────────

describe('P15.04 — triage-ticket path (gate enabled)', () => {
  it('emits review_clean_recorded when reconciled outcome is clean', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const ticket = makeTicket(TICKET_ID, {
      status: 'done',
      reviewOutcome: 'clean',
    });
    const state = makeState(PLAN_KEY, [ticket]);
    const events = eventsForReconcileLateReviewCommand(state, TICKET_ID);

    await maybeEmitReviewCleanRecorded(events, config, root);

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('review_clean_recorded');
    expect(parsed.plan_key).toBe(PLAN_KEY);
    expect(parsed.ticket_id).toBe(TICKET_ID);
  });
});

// ─── gate disabled ────────────────────────────────────────────────────────────

describe('P15.04 — codogotchi.enabled: false suppresses all paths', () => {
  it('does not emit for record-review clean when gate is disabled', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();
    const ticket = makeTicket(TICKET_ID, {
      status: 'reviewed',
      reviewOutcome: 'clean',
    });
    const state = makeState(PLAN_KEY, [ticket]);
    const events = eventsForRecordReviewCommand(state, TICKET_ID);

    await maybeEmitReviewCleanRecorded(events, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });

  it('does not emit for poll-review clean when gate is disabled', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();
    const ticket = makeTicket(TICKET_ID, {
      status: 'reviewed',
      reviewOutcome: 'clean',
    });
    const state = makeState(PLAN_KEY, [ticket]);
    const events = eventsForPollReviewCommand(state, TICKET_ID);

    await maybeEmitReviewCleanRecorded(events, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });

  it('does not emit for triage-ticket clean when gate is disabled', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();
    const ticket = makeTicket(TICKET_ID, {
      status: 'done',
      reviewOutcome: 'clean',
    });
    const state = makeState(PLAN_KEY, [ticket]);
    const events = eventsForReconcileLateReviewCommand(state, TICKET_ID);

    await maybeEmitReviewCleanRecorded(events, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });
});
