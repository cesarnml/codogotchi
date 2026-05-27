import { existsSync, mkdirSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import { emitSoaEventsForTransitions } from '../cli-runner';
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
    `p15-02-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  mkdirSync(dir, { recursive: true });
  return dir;
}

function makeTicket(id: string, status: TicketState['status']): TicketState {
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

const PLAN_KEY = 'phase-15';

describe('P15.02 — emitSoaEventsForTransitions (gate enabled)', () => {
  it('emits ticket_started when start transitions a ticket from pending to in_progress', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    const previous = makeState(PLAN_KEY, [makeTicket('P15.02', 'pending')]);
    const next = makeState(PLAN_KEY, [makeTicket('P15.02', 'in_progress')]);

    await emitSoaEventsForTransitions(previous, next, config, root);

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('ticket_started');
    expect(parsed.plan_key).toBe(PLAN_KEY);
    expect(parsed.ticket_id).toBe('P15.02');
  });

  it('appends ticket_completed when advance transitions in_progress → done', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    const previous = makeState(PLAN_KEY, [makeTicket('P15.02', 'in_progress')]);
    const next = makeState(PLAN_KEY, [makeTicket('P15.02', 'done')]);

    await emitSoaEventsForTransitions(previous, next, config, root);

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(1);
    const parsed = JSON.parse(lines[0]!);
    expect(parsed.name).toBe('ticket_completed');
    expect(parsed.plan_key).toBe(PLAN_KEY);
    expect(parsed.ticket_id).toBe('P15.02');
  });

  it('emits ticket_completed(A) then ticket_started(B) when advance transitions both', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    const previous = makeState(PLAN_KEY, [
      makeTicket('P15.01', 'in_progress'),
      makeTicket('P15.02', 'pending'),
    ]);
    const next = makeState(PLAN_KEY, [
      makeTicket('P15.01', 'done'),
      makeTicket('P15.02', 'in_progress'),
    ]);

    await emitSoaEventsForTransitions(previous, next, config, root);

    const content = await readFile(join(root, '.soa', 'events.ndjson'), 'utf8');
    const lines = content.trim().split('\n');
    expect(lines).toHaveLength(2);
    const first = JSON.parse(lines[0]!);
    const second = JSON.parse(lines[1]!);
    expect(first.name).toBe('ticket_completed');
    expect(first.ticket_id).toBe('P15.01');
    expect(second.name).toBe('ticket_started');
    expect(second.ticket_id).toBe('P15.02');
  });
});

describe('P15.02 — emitSoaEventsForTransitions (gate disabled)', () => {
  it('does not create .soa/events.ndjson when codogotchi.enabled is false', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();

    const previous = makeState(PLAN_KEY, [makeTicket('P15.02', 'pending')]);
    const next = makeState(PLAN_KEY, [makeTicket('P15.02', 'in_progress')]);

    await emitSoaEventsForTransitions(previous, next, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);

    // Also verify advance-path transitions are suppressed
    const previous2 = makeState(PLAN_KEY, [
      makeTicket('P15.02', 'in_progress'),
    ]);
    const next2 = makeState(PLAN_KEY, [makeTicket('P15.02', 'done')]);

    await emitSoaEventsForTransitions(previous2, next2, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });
});
