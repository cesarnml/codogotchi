import { existsSync, mkdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import { emitReviewCleanGate } from '../cli-runner';
import {
  eventsForPollReviewCommand,
  eventsForReconcileLateReviewCommand,
  eventsForRecordReviewCommand,
} from '../notifications';
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

function makeTmpDir(): string {
  const dir = join(
    tmpdir(),
    `p17-04-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(dir, { recursive: true });
  return dir;
}

async function readGate(home: string): Promise<Record<string, unknown>> {
  const raw = await readFile(join(home, 'gate.json'), 'utf8');
  return JSON.parse(raw) as Record<string, unknown>;
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

const PLAN_KEY = 'phase-17';
const TICKET_ID = 'P17.04';

describe('P17.04 — emitReviewCleanGate (record-review path)', () => {
  it('writes review_clean when record-review outcome is clean', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket(TICKET_ID, {
        status: 'reviewed',
        reviewOutcome: 'clean',
      });
      const state = makeState(PLAN_KEY, [ticket]);
      const events = eventsForRecordReviewCommand(state, TICKET_ID);

      await emitReviewCleanGate(events, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('review_clean');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe(TICKET_ID);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('does not write gate.json when outcome is needs_patch', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket(TICKET_ID, {
        status: 'needs_patch',
        reviewOutcome: 'needs_patch',
      });
      const state = makeState(PLAN_KEY, [ticket]);
      const events = eventsForRecordReviewCommand(state, TICKET_ID);

      await emitReviewCleanGate(events, enabledConfig(), PLAN_KEY);

      expect(existsSync(join(home, 'gate.json'))).toBe(false);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.04 — emitReviewCleanGate (poll-review path)', () => {
  it('writes review_clean when poll-review resolves clean', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket(TICKET_ID, {
        status: 'reviewed',
        reviewOutcome: 'clean',
      });
      const state = makeState(PLAN_KEY, [ticket]);
      const events = eventsForPollReviewCommand(state, TICKET_ID);

      await emitReviewCleanGate(events, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('review_clean');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe(TICKET_ID);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('does not write gate.json when poll-review outcome is skipped (doc-only fast path)', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket(TICKET_ID, {
        status: 'reviewed',
        reviewOutcome: 'skipped',
      });
      const state = makeState(PLAN_KEY, [ticket]);
      const events = eventsForPollReviewCommand(state, TICKET_ID);

      await emitReviewCleanGate(events, enabledConfig(), PLAN_KEY);

      expect(existsSync(join(home, 'gate.json'))).toBe(false);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.04 — emitReviewCleanGate (triage-ticket path)', () => {
  it('writes review_clean when triage-ticket reconciles clean', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket(TICKET_ID, {
        status: 'done',
        reviewOutcome: 'clean',
      });
      const state = makeState(PLAN_KEY, [ticket]);
      const events = eventsForReconcileLateReviewCommand(state, TICKET_ID);

      await emitReviewCleanGate(events, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('review_clean');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe(TICKET_ID);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.04 — no events.ndjson created', () => {
  it('does not create .soa/events.ndjson anywhere (NDJSON retired)', async () => {
    // Verify soa-event-feed.ts is no longer importable / referenced
    // by checking that no .soa directory appears after a clean emit call
    const home = makeTmpDir();
    const soaDir = join(home, '.soa');
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket(TICKET_ID, {
        status: 'reviewed',
        reviewOutcome: 'clean',
      });
      const state = makeState(PLAN_KEY, [ticket]);
      const events = eventsForRecordReviewCommand(state, TICKET_ID);

      await emitReviewCleanGate(events, enabledConfig(), PLAN_KEY);

      // gate.json should be written but .soa/ directory should NOT exist
      expect(existsSync(join(home, 'gate.json'))).toBe(true);
      expect(existsSync(soaDir)).toBe(false);
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});
