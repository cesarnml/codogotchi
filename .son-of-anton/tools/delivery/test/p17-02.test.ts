import { existsSync, mkdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import {
  emitGateForTransitions,
  emitStartExitGate,
  emitPostRedGate,
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

function gatedConfig(): ResolvedOrchestratorConfig {
  return { ...enabledConfig(), ticketBoundaryMode: 'gated' };
}

function makeTmpDir(): string {
  const dir = join(
    tmpdir(),
    `p17-02-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
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
  status: TicketState['status'],
  redPolicy: 'required' | 'skip' = 'required',
): TicketState {
  return {
    id,
    title: `Ticket ${id}`,
    slug: id.toLowerCase(),
    redPolicy,
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

describe('P17.02 — emitStartExitGate', () => {
  it('writes red_tdd when ticket redPolicy is required', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket('P17.02', 'in_progress', 'required');
      await emitStartExitGate(ticket, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('red_tdd');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.02');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('writes green_tdd when ticket redPolicy is skip', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket('P17.02', 'in_progress', 'skip');
      await emitStartExitGate(ticket, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('green_tdd');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.02');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.02 — emitPostRedGate', () => {
  it('writes green_tdd when post-red completes', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const ticket = makeTicket('P17.02', 'red_complete', 'required');
      await emitPostRedGate(ticket, enabledConfig(), PLAN_KEY);

      const gate = await readGate(home);
      expect(gate['gate']).toBe('green_tdd');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.02');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});

describe('P17.02 — emitGateForTransitions (replaces emitSoaEventsForTransitions)', () => {
  it('writes ticket_completed when ticket transitions in_progress → done (gated)', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const prev = makeState(PLAN_KEY, [makeTicket('P17.02', 'in_progress')]);
      const next = makeState(PLAN_KEY, [makeTicket('P17.02', 'done')]);

      await emitGateForTransitions(prev, next, gatedConfig());

      expect(existsSync(join(home, 'gate.json'))).toBe(true);
      const gate = await readGate(home);
      expect(gate['gate']).toBe('ticket_completed');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.02');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('cook-mode: writes ticket_started (next ticket) as resident gate when advancing', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const prev = makeState(PLAN_KEY, [
        makeTicket('P17.01', 'in_progress'),
        makeTicket('P17.02', 'pending'),
      ]);
      const next = makeState(PLAN_KEY, [
        makeTicket('P17.01', 'done'),
        makeTicket('P17.02', 'in_progress'),
      ]);

      await emitGateForTransitions(prev, next, enabledConfig());

      // Last write wins: ticket_started for P17.02 overwrites ticket_completed for P17.01
      const gate = await readGate(home);
      expect(gate['gate']).toBe('ticket_started');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.02');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('cook-mode: ticket_started is resident even when pending ticket is first in array', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      // Reversed array order: pending first, in_progress second
      const prev = makeState(PLAN_KEY, [
        makeTicket('P17.02', 'pending'),
        makeTicket('P17.01', 'in_progress'),
      ]);
      const next = makeState(PLAN_KEY, [
        makeTicket('P17.02', 'in_progress'),
        makeTicket('P17.01', 'done'),
      ]);

      await emitGateForTransitions(prev, next, enabledConfig());

      // Two-pass emission guarantees ticket_started is last regardless of array order
      const gate = await readGate(home);
      expect(gate['gate']).toBe('ticket_started');
      expect(gate['ticket_id']).toBe('P17.02');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });

  it('writes ticket_started when a ticket transitions pending → in_progress', async () => {
    const home = makeTmpDir();
    process.env['CODOGOTCHI_HOME'] = home;
    try {
      const prev = makeState(PLAN_KEY, [makeTicket('P17.02', 'pending')]);
      const next = makeState(PLAN_KEY, [makeTicket('P17.02', 'in_progress')]);

      await emitGateForTransitions(prev, next, enabledConfig());

      const gate = await readGate(home);
      expect(gate['gate']).toBe('ticket_started');
      expect(gate['plan_key']).toBe(PLAN_KEY);
      expect(gate['ticket_id']).toBe('P17.02');
    } finally {
      delete process.env['CODOGOTCHI_HOME'];
    }
  });
});
