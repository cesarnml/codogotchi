import { existsSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'bun:test';

import { emitSoaEventForOpenPr } from '../cli-runner';
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
    `p15-03-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
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
const VALID_PR_OPENED_AT = '2026-05-23T09:05:47.337Z';

// Phase 17 retired the pr_review_window_opened NDJSON emission from
// emitSoaEventForOpenPr. The open_pr gate now emits to gate.json via
// emitOpenPrGate in the open-pr handler. The function is a no-op stub
// retained for backwards-compatible call sites and will be removed in P17.04.
describe('P15.03 — emitSoaEventForOpenPr (retired NDJSON emission)', () => {
  it('does not create .soa/events.ndjson even when ticket has prUrl and prOpenedAt', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const ticket = makeTicket('P15.03', {
      prUrl: 'https://github.com/org/repo/pull/99',
      prOpenedAt: VALID_PR_OPENED_AT,
    });
    const state = makeState(PLAN_KEY, [ticket]);

    await emitSoaEventForOpenPr(state, config, root, 'P15.03');

    expect(existsSync(join(root, '.soa', 'events.ndjson'))).toBe(false);
  });

  it('does not create .soa/ for any ticket configuration (retired behavior)', async () => {
    const root = makeTmpDir();
    const config = enabledConfig();
    const ticket = makeTicket('P15.03');
    const state = makeState(PLAN_KEY, [ticket]);

    await emitSoaEventForOpenPr(state, config, root, 'P15.03');

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });
});

describe('P15.03 — emitSoaEventForOpenPr (gate disabled)', () => {
  it('does not create .soa/events.ndjson when codogotchi.enabled is false', async () => {
    const root = makeTmpDir();
    const config = disabledConfig();
    const ticket = makeTicket('P15.03', {
      prUrl: 'https://github.com/org/repo/pull/99',
      prOpenedAt: VALID_PR_OPENED_AT,
    });
    const state = makeState(PLAN_KEY, [ticket]);

    await emitSoaEventForOpenPr(state, config, root, 'P15.03');

    expect(existsSync(join(root, '.soa'))).toBe(false);
  });
});
