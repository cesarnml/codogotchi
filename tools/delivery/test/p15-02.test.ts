import { existsSync, mkdirSync } from 'node:fs';
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

// Phase 17 retired the ticket_started/ticket_completed NDJSON emission from
// emitSoaEventsForTransitions. These events now write to gate.json via
// emitGateForTransitions. The function is a no-op stub retained for
// backwards-compatible call sites and will be removed in P17.04.
describe('P15.02 — emitSoaEventsForTransitions (retired NDJSON emission)', () => {
  it('does not create .soa/events.ndjson for pending → in_progress (retired behavior)', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    const previous = makeState(PLAN_KEY, [makeTicket('P15.02', 'pending')]);
    const next = makeState(PLAN_KEY, [makeTicket('P15.02', 'in_progress')]);

    await emitSoaEventsForTransitions(previous, next, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });

  it('does not create .soa/events.ndjson for in_progress → done (retired behavior)', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();

    const previous = makeState(PLAN_KEY, [makeTicket('P15.02', 'in_progress')]);
    const next = makeState(PLAN_KEY, [makeTicket('P15.02', 'done')]);

    await emitSoaEventsForTransitions(previous, next, config, root);

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });

  it('does not create .soa/events.ndjson for cook-mode advance (retired behavior)', async () => {
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

    expect(existsSync(join(root, '.soa'))).toBe(false);
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
  });
});
