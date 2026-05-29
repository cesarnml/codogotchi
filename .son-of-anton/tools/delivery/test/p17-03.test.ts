import { existsSync, mkdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import {
  emitAdversarialReviewGate,
  emitOpenPrGate,
  emitPollReviewGate,
  emitRecordReviewGate,
  emitSoaEventForOpenPr,
} from '../cli-runner';
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
    `p17-03-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(dir, { recursive: true });
  return dir;
}

async function readGate(home: string): Promise<Record<string, unknown>> {
  const raw = await readFile(join(home, 'gate.json'), 'utf8');
  return JSON.parse(raw) as Record<string, unknown>;
}

function makeTicket(
  id: string,
  status: TicketState['status'] = 'in_review',
): TicketState {
  return {
    id,
    title: `Ticket ${id}`,
    slug: id.toLowerCase(),
    redPolicy: 'required',
    ticketFile: `docs/delivery/ticket-${id}.md`,
    status,
    branch: `agents/${id}`,
    baseBranch: 'main',
    worktreePath: '/tmp/fake',
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

describe('P17.03 — emitAdversarialReviewGate', () => {
  it('writes adversarial_review with correct plan_key and ticket_id', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket('P17.03', 'verified');
      await emitAdversarialReviewGate(ticket, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('adversarial_review');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.03');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.03 — emitOpenPrGate', () => {
  it('writes open_pr with correct plan_key and ticket_id', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket('P17.03', 'subagent_review_complete');
      await emitOpenPrGate(ticket, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('open_pr');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.03');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.03 — emitPollReviewGate', () => {
  it('writes poll_review with correct plan_key and ticket_id', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket('P17.03', 'in_review');
      await emitPollReviewGate(ticket, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('poll_review');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.03');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.03 — emitRecordReviewGate', () => {
  it('writes record_review with correct plan_key and ticket_id', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket('P17.03', 'in_review');
      await emitRecordReviewGate(ticket, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('record_review');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.03');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.03 — emitSoaEventForOpenPr (retired pr_review_window_opened NDJSON)', () => {
  it('does not create .soa/events.ndjson (pr_review_window_opened retired in P17.03)', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const ticket = makeTicket('P17.03', 'in_review');
    const state = makeState(PLAN_KEY, [
      {
        ...ticket,
        prUrl: 'https://github.com/org/repo/pull/99',
        prOpenedAt: '2026-05-29T12:00:00.000Z',
      },
    ]);

    // emitSoaEventForOpenPr is now a no-op; open_pr gate goes to gate.json via emitOpenPrGate
    await emitSoaEventForOpenPr(state, config, root, 'P17.03');

    expect(existsSync(join(root, '.soa', 'events.ndjson'))).toBe(false);
  });
});
