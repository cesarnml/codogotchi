import { mkdirSync } from 'node:fs';
import { open } from 'node:fs/promises';
import { join } from 'node:path';

import type { ResolvedOrchestratorConfig } from './config';
import type { DeliveryNotificationEvent } from './types';

export type SoaEventLine = {
  name: string;
  ts: string;
  plan_key?: string;
  ticket_id?: string;
  payload?: Record<string, unknown>;
};

export function buildSoaEventLine(
  name: string,
  opts?: {
    plan_key?: string;
    ticket_id?: string;
    payload?: Record<string, unknown>;
  },
): SoaEventLine {
  const line: SoaEventLine = { name, ts: new Date().toISOString() };
  if (opts?.plan_key !== undefined) line.plan_key = opts.plan_key;
  if (opts?.ticket_id !== undefined) line.ticket_id = opts.ticket_id;
  if (opts?.payload !== undefined) line.payload = opts.payload;
  return line;
}

export async function appendSoaEvent(
  config: ResolvedOrchestratorConfig,
  projectRoot: string,
  event: SoaEventLine,
): Promise<void> {
  try {
    if (config.codogotchi?.enabled === false) return;
    const soaDir = join(projectRoot, '.soa');
    mkdirSync(soaDir, { recursive: true });
    const filePath = join(soaDir, 'events.ndjson');
    const fh = await open(filePath, 'a');
    try {
      await fh.write(JSON.stringify(event) + '\n');
    } finally {
      await fh.close();
    }
  } catch {
    // best-effort: write failures never abort a delivery command
  }
}

export async function emitSubagentInvoked(
  config: ResolvedOrchestratorConfig,
  worktreePath: string,
  planKey: string,
  ticketId: string,
  runnerKind: 'claude-cli' | 'codex-cli' | 'cursor-cli',
): Promise<void> {
  await appendSoaEvent(
    config,
    worktreePath,
    buildSoaEventLine('subagent_invoked', {
      plan_key: planKey,
      ticket_id: ticketId,
      payload: { runnerKind },
    }),
  );
}

export async function maybeEmitReviewCleanRecorded(
  events: DeliveryNotificationEvent[],
  config: ResolvedOrchestratorConfig,
  projectRoot: string,
): Promise<void> {
  const reviewEvent = events.find(
    (e): e is Extract<DeliveryNotificationEvent, { kind: 'review_recorded' }> =>
      e.kind === 'review_recorded' && e.outcome === 'clean',
  );
  if (reviewEvent) {
    await appendSoaEvent(
      config,
      projectRoot,
      buildSoaEventLine('review_clean_recorded', {
        plan_key: reviewEvent.planKey,
        ticket_id: reviewEvent.ticketId,
      }),
    );
  }
}
